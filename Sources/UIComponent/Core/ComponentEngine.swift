//
//  File.swift
//  
//
//  Created by Luke Zhao on 8/27/20.
//

import UIKit

public class ComponentEngine {
  public weak var view: ComponentDisplayableView?
  public var component: Component? {
    didSet { setNeedsReload() }
  }
  public var animator: Animator = Animator() {
    didSet { setNeedsReload() }
  }
  
  public private(set) var renderer: Renderer?
  
  public internal(set) var needsReload = true
  public internal(set) var needsLoadCell = false
  public private(set) var reloadCount = 0
  public private(set) var isLoadingCell = false
  public private(set) var isReloading = false
  public var hasReloaded: Bool { reloadCount > 0 }

  // visible identifiers for cells on screen
  public private(set) var visibleCells: [UIView] = []
  public private(set) var visibleViewData: [Renderable] = []

  public private(set) var lastLoadBounds: CGRect = .zero
  public private(set) var contentOffsetChange: CGPoint = .zero

  public var centerContentViewVertically = false
  public var centerContentViewHorizontally = true
  public var contentView: UIView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let contentView = contentView {
        view?.addSubview(contentView)
      }
    }
  }
  public var contentSize: CGSize = .zero {
    didSet {
      (view as? UIScrollView)?.contentSize = contentSize
    }
  }
  public var contentOffset: CGPoint {
    get { return view?.bounds.origin ?? .zero }
    set { view?.bounds.origin = newValue }
  }
  public var contentInset: UIEdgeInsets {
    guard let view = view as? UIScrollView else { return .zero }
    return view.adjustedContentInset
  }
  public var bounds: CGRect {
    guard let view = view else { return .zero }
    return view.bounds
  }
  public var adjustedSize: CGSize {
    bounds.size.inset(by: contentInset)
  }
  public var zoomScale: CGFloat {
    guard let view = view as? UIScrollView else { return 1 }
    return view.zoomScale
  }

  private var visibleIdentifiers: [String] = []
  private var shouldSkipLayout = false
  
  init(view: ComponentDisplayableView) {
    self.view = view
  }
  
  func layoutSubview() {
    if needsReload {
      reloadData()
    } else if bounds.size != lastLoadBounds.size {
      invalidateLayout()
    } else if bounds != lastLoadBounds || needsLoadCell {
      _loadCells()
    }
    contentView?.frame = CGRect(origin: .zero, size: contentSize)
    ensureZoomViewIsCentered()
  }

  public func ensureZoomViewIsCentered() {
    guard let contentView = contentView else { return }
    let boundsSize: CGRect
    boundsSize = bounds.inset(by: contentInset)
    var frameToCenter = contentView.frame

    if centerContentViewHorizontally, frameToCenter.size.width < boundsSize.width {
      frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) * 0.5
    } else {
      frameToCenter.origin.x = 0
    }

    if centerContentViewVertically, frameToCenter.size.height < boundsSize.height {
      frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) * 0.5
    } else {
      frameToCenter.origin.y = 0
    }

    contentView.frame = frameToCenter
  }

  public func setNeedsReload() {
    needsReload = true
    view?.setNeedsLayout()
  }

  public func setNeedsInvalidateLayout() {
    renderer = nil
    setNeedsLoadCells()
  }

  public func setNeedsLoadCells() {
    needsLoadCell = true
    view?.setNeedsLayout()
  }

  // re-layout, but not updating cells' contents
  public func invalidateLayout() {
    guard !isLoadingCell, !isReloading, hasReloaded else { return }
    renderer = nil
    _loadCells()
  }

  // reload all frames. will automatically diff insertion & deletion
  public func reloadData(contentOffsetAdjustFn: (() -> CGPoint)? = nil) {
    guard let component = component, !isReloading else { return }
    isReloading = true
    defer {
      needsReload = false
      isReloading = false
      shouldSkipLayout = false
    }

    if !shouldSkipLayout {
      renderer = component.layout(Constraint(maxSize: adjustedSize))
      contentSize = renderer!.size * zoomScale

      let oldContentOffset = contentOffset
      if let offset = contentOffsetAdjustFn?() {
        contentOffset = offset
      }
      contentOffsetChange = contentOffset - oldContentOffset
    }

    _loadCells()

    reloadCount += 1
  }

  private func _loadCells() {
    guard let view = view, !isLoadingCell, let component = component else { return }
    isLoadingCell = true
    defer {
      needsLoadCell = false
      isLoadingCell = false
    }
    
    let renderer: Renderer
    if let currentRenderer = self.renderer {
      renderer = currentRenderer
    } else {
      renderer = component.layout(Constraint(maxSize: adjustedSize))
      contentSize = renderer.size * zoomScale
      self.renderer = renderer
    }

    animator.willUpdate(componentView: view)
    let visibleFrame = contentView?.convert(bounds, from: view) ?? bounds
    
    let newVisibleViewData = renderer.views(in: visibleFrame)
    if contentSize != renderer.size * zoomScale {
      // update contentSize if it is changed. Some renderers update
      // its size when views(in: visibleFrame) is called. e.g. InfiniteLayout
      contentSize = renderer.size * zoomScale
    }

    // construct private identifiers
    var newIdentifierSet = [String: Int]()
    let newIdentifiers: [String] = newVisibleViewData.enumerated().map { index, viewData in
      let identifier = viewData.id
      var finalIdentifier = identifier
      var count = 1
      while newIdentifierSet[finalIdentifier] != nil {
        finalIdentifier = identifier + String(count)
        count += 1
      }
      newIdentifierSet[finalIdentifier] = index
      return finalIdentifier
    }

    var newCells = [UIView?](repeating: nil, count: newVisibleViewData.count)

    // 1st pass, delete all removed cells and move existing cells
    for index in 0 ..< visibleCells.count {
      let identifier = visibleIdentifiers[index]
      let cell = visibleCells[index]
      if let index = newIdentifierSet[identifier] {
        newCells[index] = cell
      } else {
        (visibleViewData[index].animator ?? animator)?.delete(componentView: view,
                                                              view: cell)
      }
    }

    // 2nd pass, insert new views
    for (index, viewData) in newVisibleViewData.enumerated() {
      let cell: UIView
      let frame = viewData.frame
      if let existingCell = newCells[index] {
        cell = existingCell
        if isReloading {
          // cell was on screen before reload, need to update the view.
          viewData.renderer._updateView(cell)
          (viewData.animator ?? animator).shift(componentView: view,
                                                delta: contentOffsetChange,
                                                view: cell,
                                                frame: frame)
        }
      } else {
        cell = viewData.renderer._makeView()
        viewData.renderer._updateView(cell)
        UIView.performWithoutAnimation {
          cell.bounds.size = frame.bounds.size
          cell.center = frame.center
        }
        (viewData.animator ?? animator).insert(componentView: view,
                                               view: cell,
                                               frame: frame)
        newCells[index] = cell
      }
      (viewData.animator ?? animator).update(componentView: view,
                                             view: cell,
                                             frame: frame)
      (contentView ?? view).insertSubview(cell, at: index)
    }

    visibleIdentifiers = newIdentifiers
    visibleViewData = newVisibleViewData
    visibleCells = newCells as! [UIView]
    lastLoadBounds = bounds
  }
  
  // This function assigns component with an already calculated renderer
  // This is a performance hack that skips layout for the component if it has already
  // been layed out.
  public func updateWithExisting(component: Component, renderer: Renderer) {
    self.component = component
    self.renderer = renderer
    self.shouldSkipLayout = true
  }

  open func sizeThatFits(_ size: CGSize) -> CGSize {
    return component?.layout(Constraint(maxSize: size)).size ?? .zero
  }
}

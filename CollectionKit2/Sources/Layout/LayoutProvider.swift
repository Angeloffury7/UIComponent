//
//  LayoutProvider.swift
//  CollectionKit2
//
//  Created by Luke Zhao on 2019-01-07.
//  Copyright © 2019 Luke Zhao. All rights reserved.
//

import UIKit

open class LayoutProvider: MultiChildProvider {
  public private(set) var frames: [CGRect] = []
  open var transposed = false

  open func simpleLayout(size: CGSize) -> [CGRect] {
    fatalError("Subclass should provide its own layout")
  }

  open func doneLayout() {

  }

  open func getSize(child: Provider, maxSize: CGSize) -> CGSize {
    if transposed {
      return child.layout(size: maxSize.transposed).transposed
    }
    return child.layout(size: maxSize)
  }

  open override func layout(size: CGSize) -> CGSize {
    if transposed {
      frames = simpleLayout(size: size.transposed).map { $0.transposed }
    } else {
      frames = simpleLayout(size: size)
    }
    let contentSize = frames.reduce(CGRect.zero) { (old, item) in
      old.union(item)
      }.size
    doneLayout()
    return contentSize
  }

  open override func views(in frame: CGRect) -> [(ViewProvider, CGRect)] {
    var result = [(ViewProvider, CGRect)]()
    for (i, childFrame) in frames.enumerated() where frame.intersects(childFrame) {
      let child = children[i]
      let childResult = child.views(in: frame.intersection(childFrame) - childFrame.origin).map { ($0.0, CGRect(origin: $0.1.origin + childFrame.origin, size: $0.1.size)) }
      result.append(contentsOf: childResult)
    }
    return result
  }
}

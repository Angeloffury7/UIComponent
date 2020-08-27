//
//  FitViewProvider.swift
//  CollectionKit3
//
//  Created by Luke Zhao on 2019-01-24.
//  Copyright © 2019 Luke Zhao. All rights reserved.
//

import UIKit

public class FitViewProvider<View: UIView>: SimpleViewProvider<View> {
	public init(
		id: String = UUID().uuidString,
		animator: Animator? = nil,
		width: CGFloat? = nil,
		height: CGFloat? = nil,
		view: View
	) {
		super.init(id: id, animator: animator,
							 width: width == nil ? .fit : .absolute(width!),
							 height: height == nil ? .fit : .absolute(height!),
							 view: view)
	}
}
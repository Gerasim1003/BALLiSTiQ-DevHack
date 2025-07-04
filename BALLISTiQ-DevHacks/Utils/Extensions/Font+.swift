//
//  PoppinsFontStyle.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//

import Foundation
import SwiftUI

enum PoppinsFontStyle: String {
    case bold           = "Poppins-Bold"
    case medium         = "Poppins-Medium"
    case regular        = "Poppins-Regular"
    case semiBold       = "Poppins-SemiBold"
}

extension Font {
    static func poppinsFont(style: PoppinsFontStyle, size: CGFloat) -> Self {
        return .custom(style.rawValue, size: size)
    }
}

struct PoppinsFontModifier: ViewModifier {
    let style: PoppinsFontStyle
    var size: CGFloat

    func body(content: Content) -> some View {
        content.font(.custom(style.rawValue, size: size))
    }
}

extension View {
    func poppinsFont(size: CGFloat, style: PoppinsFontStyle = .regular) -> some View {
        modifier(PoppinsFontModifier(style: style, size: size))
    }
}

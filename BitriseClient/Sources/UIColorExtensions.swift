import UIKit

extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(hex & 0x0000FF) / 255.0

        self.init(displayP3Red: red, green: green, blue: blue, alpha: alpha)
    }

    static let baseGreen = UIColor(hex: 0x4BBFA8)
    static let gitGreen = UIColor(hex: 0x4BBF00)
    static let gitGreenHighlight = UIColor(hex: 0x3A9401)
}

import SwiftData
import Foundation
import EnsemblesSwiftData

@Model
final class NumberItem: Syncable {
    static let globalIdentifierKey = "uniqueID"
    var uniqueID: String
    var number: Int

    init(uniqueID: String = "NumberItem", number: Int = 0) {
        self.uniqueID = uniqueID
        self.number = number
    }
}

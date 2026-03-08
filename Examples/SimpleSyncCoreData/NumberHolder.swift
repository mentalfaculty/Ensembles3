import Foundation
import CoreData

class NumberHolder: NSManagedObject {

    @NSManaged var uniqueIdentifier: String
    @NSManaged var number: NSNumber

    static func numberHolder(in context: NSManagedObjectContext) -> NumberHolder {
        var holder: NumberHolder?
        context.performAndWait {
            let fetch = NSFetchRequest<NumberHolder>(entityName: "NumberHolder")
            holder = try? context.fetch(fetch).last
            if holder == nil {
                holder = NumberHolder(context: context)
                holder?.uniqueIdentifier = "NumberHolder"
                holder?.number = NSNumber(value: 0)
            }
        }
        return holder!
    }
}

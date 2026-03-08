import SwiftUI
import CoreData

struct DeviceView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: NSFetchRequest<NumberHolder>(entityName: "NumberHolder"))
    private var holders: FetchedResults<NumberHolder>

    var body: some View {
        VStack(spacing: 40) {
            Text("\(holders.first?.number.intValue ?? 0)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())

            Button("Randomize") {
                let holder = holders.first ?? NumberHolder.numberHolder(in: context)
                var newNumber: Int
                repeat {
                    newNumber = Int.random(in: 0..<100)
                } while newNumber == holder.number.intValue

                holder.number = NSNumber(value: newNumber)
                try? context.save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

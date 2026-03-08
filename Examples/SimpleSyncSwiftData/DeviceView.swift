import SwiftUI
import SwiftData

struct DeviceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [NumberItem]

    var body: some View {
        VStack(spacing: 40) {
            Text("\(items.first?.number ?? 0)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())

            Button("Randomize") {
                let item = items.first ?? {
                    let new = NumberItem()
                    modelContext.insert(new)
                    return new
                }()

                var newNumber: Int
                repeat {
                    newNumber = Int.random(in: 0..<100)
                } while newNumber == item.number

                item.number = newNumber
                try? modelContext.save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .onAppear {
            if items.isEmpty {
                let item = NumberItem()
                modelContext.insert(item)
                try? modelContext.save()
            }
        }
    }
}

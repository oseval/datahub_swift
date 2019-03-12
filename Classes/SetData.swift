/**
 * Data to help operating with collections inside at-least-once and eff-once Data wrappers.
 * This class adds to collection "diffFromClock" ability.
 */
struct SetData<A> {
    let added: [Int64 : A] // Int64 -> A
    let removed: [Int64 : A] // Int64 -> A
    
//    let zero: () -> SetData<A> = { return SetData() }
    
    let actualMap: [Int64 : A]
    let elements: [A]
    let lastClockOpt: Int64?
    let removedElements: [A]
    
    func diffFromClock(a: SetData<A>, from: Int64) -> SetData<A> {
        return SetData(
            added: a.added.filter { $0.key > from },
            removed: a.removed.filter { $0.key > from }
        )
    }
    
    func one(element: A, clock: Int64) -> SetData<A> {
        return SetData(added: [clock : element], removed: [:])
    }
    
    func apply<A>(clock: Int64, elements: A...) -> SetData<A> {
        let initial: ([Int64 : A], Int64) = ([:], clock)
        let reduced = elements.reduce(initial, { res, el in
            var newRes: [Int64 : A] = res.0
            newRes[res.1] = el
            return (newRes, res.1 + 1)
        })
        
        return SetData<A>(added: reduced.0, removed: [:])
    }

    
    func add(el: A, newClock: Int64) -> SetData<A> {
        var newAdded = [Int64 : A]()
        added.forEach { newAdded.updateValue($0.1, forKey: $0.0) }
        newAdded[newClock] = el
        return SetData(added: newAdded, removed: removed)
    }
    
    func remove(el: A, newClock: Int64) -> SetData<A> {
        var newRemoved = [Int64 : A]()
        removed.forEach { newRemoved.updateValue($0.1, forKey: $0.0) }
        newRemoved[newClock] = el
        return SetData(added: added, removed: newRemoved)
    }
    
    init(added: [Int64 : A] = [:], removed: [Int64 : A] = [:]) {
        self.added = added
        self.removed = removed
        
        let actualM = added.filter { removed[$0.0] == nil }
        self.actualMap = actualM
        self.elements = self.actualMap.values.map { $0 }
        
        self.removedElements = removed.filter { actualM[$0.0] == nil }.map { $0.1 }
        
        let allClocks = added.keys.map { $0 } + removed.keys.map { $0 }
        self.lastClockOpt = allClocks.count > 0 ? allClocks.max() : nil
    }
}

struct DHInvalidDataException: Error {
    let error: String
}

class ALODataOps<AO: DHDataOps>: DHDataOps {
    let kind: String
    let genZero: DHDataGen
    
    let ops: AO
    typealias Dt = ALOData<AO.Dt>
    
    let gt: (Dt.C, Dt.C) -> Bool
    let zero: Dt
    
    init(ops: AO) {
        self.ops = ops
        self.kind = ops.kind
        self.zero = ALOData(data: ops.zero, clock: ops.zero.clock, previousClock: ops.zero.clock, further: nil)
        self.genZero = zero
        self.gt = ops.gt
    }
    
    func gteq(c1: Dt.C, c2: Dt.C) -> Bool {
        return !gt(c1, c2)
    }
    
    func getRelations(_ data: Dt) -> (Set<DHEntityGenH>, Set<DHEntityGenH>) {
        return ops.getRelations(data.data)
    }
    
    // TODO: can't be true if it is a partial data - for local storage only. Restrict access to it.
    func diffFromClock(a: ALOData<AO.Dt>, from: AO.Dt.C) throws -> ALOData<AO.Dt> {
        if (a.isSolid) {
            return ALOData(
                data: ops.diffFromClock(a.data, from),
                clock: a.clock,
                previousClock: gt(from, a.clock) ? from : a.clock,
                further: nil
            )
        } else {
            throw DHInvalidDataException(error: "Diff can't be done on a partial data")
        }
    }
    
    private func combineIntersected(_ first: Dt, _ second: Dt) -> Dt {
        return gteq(c1: first.previousClock, c2: second.previousClock) ? second : {
            let visible: Dt = ALOData(
                data: ops.combine(first.data, second.data),
                clock: second.clock,
                previousClock: first.previousClock,
                further: nil
            )
            
            var further: Dt? = nil
            
            switch (first.further, second.further) {
            case let (.some(ff), .some(sf)): further = combine(ff, sf)
            case (let .some(ff), nil): further = ff
            case (nil, let .some(sf)): further = sf
            case (nil, nil): further = nil
            }
            
            return further.map { combine(visible, $0) } ?? visible
        }()
    }
    
    func ass<A, B>(_ v: A) -> B {
        return (v as Any) as! B
    }
    
    func combine(_ a: Dt, _ b: Dt) -> Dt {
        let (first, second): (Dt, Dt) =  gt(a.clock, b.clock) ? (b, a) : (a, b)
        
        //    | --- | |---|
        //
        //    | --- |
        //       | --- |
        //
        //      | --- |
        //    | -------- |
        
        return ass({
            gteq(c1: first.clock, c2: second.previousClock) ?
            combineIntersected(first, second) :
            // further
            ALOData(
                data: ops.combine(first.data, second.data),
                clock: first.clock,
                previousClock: first.previousClock,
                further: first.further.map { combine($0, second) } ?? second
            )
        }())
    }
    
    func nextClock(_ current: AO.Dt.C) -> AO.Dt.C {
        return ops.nextClock(current)
    }
}

class ALOData<A: DHData>: DHAtLeastOnceData {
    typealias D = A
    typealias C = D.C
    let data: D
    let clock: C
    let previousClock: C
    let further: ALOData<D>?
    let isSolid: Bool
    
    init(data: D, clock: C, previousClock: C, further: ALOData<D>?) {
        self.data = data
        self.clock = clock
        self.previousClock = previousClock
        self.further = further
        self.isSolid = further == nil
    }
    
    func copy(data: D, clock: C) -> ALOData<D> {
        return ALOData(data: data, clock: clock, previousClock: self.previousClock, further: self.further)
    }
    
    func updated(updated: D) -> ALOData<D> {
        return copy(data: updated, clock: updated.clock)
    }
}

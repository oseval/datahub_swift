protocol DHDataGen {
    var genClock: Any { get }
}
protocol DHData: DHDataGen {
    associatedtype D
    associatedtype C
    var data: D { get }
    var clock: C { get }
}
extension DHData {
    var genClock: Any { get { return self.clock } }
}

protocol DHAtLeastOnceDataGen {
    var genPreviousClock: Any { get }
    var isSolid: Bool { get }
}
protocol DHAtLeastOnceData: DHData {
    var previousClock: C { get }
}
extension DHAtLeastOnceData {
    var genPreviousClock: Any { get { return self.previousClock } }
    var isSolid: Bool { get { return true } }
}

protocol DHDataOpsGen {
    var kind: String { get }
    var genGt: (Any, Any) -> Bool { get }
    var genZero: DHDataGen { get }
}
extension DHDataOpsGen {
    func liftEntity<EG: DHEntityGen, D: DHData>(_ entityGen: EG, _ data: D) -> D? {
        return type(of: data) == type(of: self.genZero) ? data : nil
    }
}
protocol DHDataOps: DHDataOpsGen {
    associatedtype Dt: DHData
    var gt: (Dt.C, Dt.C) -> Bool { get }
    var zero: Dt { get }
    func combine(_ a: Dt, _ b: Dt) -> Dt
    func diffFromClock(_ a: Dt, _ from: Dt.C) -> Dt
    func nextClock(_ current: Dt.C) -> Dt.C
    func getRelations(_ data: Dt) -> (Set<DHEntityGenH>, Set<DHEntityGenH>)
    //    var matchData: (DHDataGen) -> Dt?
}
extension DHDataOps {
    var genGt: (Any, Any) -> Bool { get { return {
        let a = $0 as! Self.Dt.C
        let b = $1 as! Self.Dt.C
        return self.gt(a, b)
        } } }
    var genZero: DHDataGen { get { return self.zero } }
    var zero: Dt { get { return self.zero } }
    
    func combine(_ a: Self.Dt, _ b: Self.Dt) -> Self.Dt {
        return gt(a.clock, b.clock) ? a : b
    }
    
    func diffFromClock(_ a: Dt, _ from: Self.Dt.C) -> Self.Dt {
        return gt(a.clock, from) ? a : self.zero
    }
    
    func getRelations(_ data: Self.Dt) -> (Set<DHEntityGenH>, Set<DHEntityGenH>) {
        return (Set(), Set())
    }
}

struct M : DHAtLeastOnceData {
    typealias C = Int
    typealias D = String
    let data: String
    let clock: Int
    let previousClock: Int
    let isSolid: Bool = true
}

struct ClockInt<C> {
    let cur: C
    let start: C
}

//       ai     alo    eff
//
//a                    +      prevId
//
//c      +      +      +      order
//
//i      +      +      +      id

//
//  DialogListData.swift
//  OEADatahub
//
//  Created by oseval on 13/03/2019.
//  Copyright © 2019 oseval. All rights reserved.
//

import Foundation

enum PeerType {
    case Private, Group
}
struct Peer {
    let tp: PeerType
    let id: Int
}

struct DialogListData: DHData {
    typealias D = SetData<Peer>
    typealias C = Int64
    
    let data: D
    let clock: Int64
    
    init(_ data: D = SetData(), _ clock: Int64 = 0) {
        self.data = data
        self.clock = clock
    }
}

class DialogListDataOpsSimple: DHDataOps {
    typealias Dt = DialogListData
    
    var kind: String { get { return "dialogs" } }
    var gt: (Int64, Int64) -> Bool = { $0 > $1 }
    static var zero: Dt { get { return DialogListData() } }
    
    func nextClock(_ current: Int64) -> Int64 {
        return Int64(NSDate().timeIntervalSince1970 * 1000)
    }
    
    func diffFromClock(_ a: Dt, _ from: Int64) -> Dt {
        return DialogListData(a.data.diffFromClock(from), a.clock)
    }
}

class DialogListDataOps: ALODataOps<DialogListDataOpsSimple> {
    static let o: DialogListDataOps = DialogListDataOps(ops: DialogListDataOpsSimple())
}

let st1 = DialogListDataOps.o.zero
let st2 = st1.copy(data: DialogListData(SetData<Peer>.one(Peer(tp: PeerType.Private, id: 111), 5), 5), clock: 5)

let res = DialogListDataOps.o.combine(st1, st2)

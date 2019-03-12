protocol DHEntityGen {
    var id: String { get }
    var genOps: DHDataOpsGen { get }
}
extension DHEntityGen {
}
struct DHEntityGenH: Hashable {
    let gen: DHEntityGen
    public var hashValue: Int { get { return self.gen.id.hashValue } }
    public static func == (lhs: DHEntityGenH, rhs: DHEntityGenH) -> Bool {
        return lhs.gen.id == rhs.gen.id
    }
}
protocol DHEntity: DHEntityGen {
    associatedtype OPS: DHDataOps
    var id: String { get }
    var ops: OPS { get }
}
extension DHEntity {
    var genOps: Any { get { return self.ops } }
}

class DHSubscriber: Hashable {
    let id: String
    func onUpdate<E: DHEntity>(_ relation: E, _ relationData: E.OPS.Dt) -> Void {
        
    }
    static func == (lhs: DHSubscriber, rhs: DHSubscriber) -> Bool {
        return lhs.id == rhs.id
    }
    public var hashValue: Int { get { return id.hashValue } }
    
    init(id: String) {
        self.id = id
    }
}

class LocalDataStorage: DHSubscriber {
    private let datahub: DHDatahub
    private let createFacade: (DHEntityGen) -> DHRemoteFacade
    private var entities: [String : DHEntityGen] = [:]
    private var relations: [String : Set<String>] = [:] // relation -> entities
    
    private var pendingSubscriptions: Set<DHEntityGenH> = Set()
    private var notSolidRelations: [DHEntityGenH : Any] = [:]
    private var datas: [String : DHDataGen] = [:]
    
    init(datahub: DHDatahub, createFacade: @escaping (DHEntityGen) -> DHRemoteFacade) {
        self.datahub = datahub
        self.createFacade = createFacade
        super.init(id: "localStorage")
    }
    
    //    private def createFacadeDep(e: Entity) = createFacade(e).asInstanceOf[LocalEntityFacade { val entity: e.type }]
    
    private func subscribeOnRelation<E: DHEntity>(entity: E, relation: DHEntityGen) -> Void {
        entities.updateValue(relation, forKey: relation.id)
        
        var ents: Set<String> = relations[relation.id] ?? []
        ents.insert(entity.id)
        relations.updateValue([], forKey: relation.id)
        
        var lastKnownData: DHDataGen
        if let dt: DHDataGen = getById(relation.id) {
            lastKnownData = dt
        } else {
            datas.updateValue(relation.genOps.genZero, forKey: relation.id)
            lastKnownData = relation.genOps.genZero
        }
        
        if (!datahub.subscribe(relation, self, lastKnownData.genClock)) {
            pendingSubscriptions.insert(DHEntityGenH(gen: relation))
        }
    }
    
    private func removeRelation(entityId: String, relationId: String) -> Void {
        relations[relationId].map { entityIds in
            var ids = entityIds
            ids.remove(entityId)
            if (ids.isEmpty) {
                entities[relationId].map { datahub.unsubscribe($0, self) }
                relations.removeValue(forKey: relationId)
                datas.removeValue(forKey: relationId)
            }
            relations[relationId] = ids
        }
    }
    
    func addEntity<E: DHEntity>(_ entity: E, _ _data: E.OPS.Dt) -> Void {
        entities.updateValue(entity as DHEntityGen, forKey: entity.id)
        let data = get(entity).map { entity.ops.combine($0, _data) } ?? _data
        
        datas.updateValue(data, forKey: entity.id)
        
        // send current clock to avoid unnecessary update sending (from zero to current)
//        datahub.register(createFacade(entity))
        
        let (addedRelations, removedRelations) = entity.ops.getRelations(data)
        
        var entityRelations = addedRelations
        entityRelations.subtract(removedRelations)
        entityRelations.forEach { subscribeOnRelation(entity: entity, relation: $0.gen) }
    }
    
//    func combineRelation<D: DHData>(_ entityId: String, _ otherData: D) -> D {
//        return entities[entityId].flatMap { e -> D? in
//            switch e.genOps.matchData(e, otherData) {
//            case let .some((e, data)):
//                return combineRelation(e, update: data) as? D
//            case .none:
////                log.warn("Data {} does not match with entity {}", String(describing: otherData), String(describing: e))
//                return otherData
//            }
//        } ?? otherData
//    }
    
    private func combineRelation<E: DHEntity>(_ entity: E, _ update: E.OPS.Dt) -> E.OPS.Dt {
        if ((relations[entity.id]) != nil) {
            let current: E.OPS.Dt = (datas[entity.id] as? E.OPS.Dt) ?? entity.ops.zero
            let updated: E.OPS.Dt = entity.ops.combine(current, update)
            
            (updated as? DHAtLeastOnceDataGen).map {
                if !$0.isSolid {
                    notSolidRelations.updateValue(current, forKey: DHEntityGenH(gen: entity))
                }
            }
    
            datas.updateValue(updated, forKey: entity.id)
    
            return updated
        } else {
//            log.warn("Entity {} is not registered as relation", entity.id)
            return update
        }
    }
    
    override func onUpdate<E: DHEntity>(_ relation: E, _ relationData: E.OPS.Dt) -> Void {
        combineRelation(relation, relationData)
    }
    
    func applyEntityUpdate<E: DHEntity>(_ entity: E, curData: E.OPS.Dt, dataUpdate: E.OPS.Dt, updatedData: E.OPS.Dt) -> Void {
        if (entities[entity.id] != nil) {
            let (addedRelations, removedRelations) = entity.ops.getRelations(dataUpdate)
            addedRelations.forEach { subscribeOnRelation(entity: entity, relation: $0.gen) }
            removedRelations.forEach { rel in removeRelation(entityId: entity.id, relationId: rel.gen.id) }
    
            datas.updateValue(updatedData, forKey: entity.id)
    
            datahub.dataUpdated(entity, dataUpdate)
        } else {
            addEntity(entity, updatedData)
        }
    }
    
    func combineEntity<E: DHEntity>(_ entity: E, upd: (E.OPS.Dt.C) -> E.OPS.Dt) -> Void {
        let curData = get(entity) ?? entity.ops.zero
        let dataUpdate = upd(entity.ops.nextClock(curData.clock))
        let updatedData = entity.ops.combine(curData, dataUpdate)
    
        applyEntityUpdate(entity, curData: curData, dataUpdate: dataUpdate, updatedData: updatedData)
    }
    
    func updateEntity<E: DHEntity>(entity: E, upd: (ClockInt<E.OPS.Dt.C>) -> ((E.OPS.Dt) -> E.OPS.Dt)) -> Void {
        let curData = get(entity) ?? entity.ops.zero
        let updatedData = upd(ClockInt(cur: entity.ops.nextClock(curData.clock), start: entity.ops.zero.clock))(curData)
        let dataUpdate = entity.ops.diffFromClock(updatedData, curData.clock)
    
        applyEntityUpdate(entity, curData: curData, dataUpdate: dataUpdate, updatedData: updatedData)
    }
    
    func diffFromClock<E: DHEntity>(_ entity: E, _ clock: E.OPS.Dt.C) -> E.OPS.Dt {
        let current = get(entity) ?? {
            datas.updateValue(entity.ops.zero, forKey: entity.id)
            return entity.ops.zero
        }()
            
        return entity.ops.diffFromClock(current, clock)
    }
    
    func getById(_ entityId: String) -> DHDataGen? {
        return datas[entityId]
    }
    
    func get<E: DHEntity>(_ entity: E) -> E.OPS.Dt? {
        return datas[entity.id].flatMap { $0 as? E.OPS.Dt }
    }
    
    /**
     * Calls of this method must be scheduled with an interval
     * @return
     */
    func checkDataIntegrity() -> Bool {
        pendingSubscriptions.forEach { relation in
            let relClock = datas[relation.gen.id].map { $0.genClock } ?? relation.gen.genOps.genZero.genClock
            if (datahub.subscribe(relation.gen, self, relClock)) {
                pendingSubscriptions.remove(relation)
            }
        }
    
        if (notSolidRelations.count > 0) {
            datahub.syncRelationClocks(self, notSolidRelations)
        }
    
        return notSolidRelations.isEmpty
    }
}

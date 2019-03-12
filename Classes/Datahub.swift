
func sync(lock: NSObject, closure: () -> Void) {
    objc_sync_enter(lock)
    closure()
    objc_sync_exit(lock)
}

private class MemoryInnerStorage {
    private func makeEmptySubscribers() -> NSMapTable<DHSubscriber, DHSubscriber> {
        return NSMapTable(keyOptions: .weakMemory, valueOptions: .weakMemory)
    }
    private let remoteFacades: NSMapTable<NSString, DHRemoteFacade> = NSMapTable()
    private let subscribers: NSMapTable<NSString, NSMapTable<DHSubscriber, DHSubscriber>> = NSMapTable() // facade -> subscribers

    func facade(_ entity: DHEntityGen) -> DHRemoteFacade? {
        return remoteFacades.object(forKey: entity.genOps.kind as NSString)
    }
    func registerFacade<F: DHRemoteFacade>(_ entityFacade: F) -> Void {
        remoteFacades.setObject(entityFacade, forKey: entityFacade.ops.kind as NSString)
    }

    func getSubscribers(_ entityId: String) -> Set<DHSubscriber> {
        let result: NSEnumerator = subscribers.object(forKey: entityId as NSString)?.keyEnumerator() ?? NSEnumerator()
        return Set(result.allObjects as! [DHSubscriber])
    }

    func addSubscriber(_ entityId: String, _ subscriber: DHSubscriber) -> Void {
        return subscribers.setObject(NSMapTable(), forKey: entityId as NSString)
    }
    func removeSubscriber(_ entity: DHEntityGen, _ subscriber: DHSubscriber) -> Void {
        if let subs = subscribers.object(forKey: entity.id as NSString) {
            subs.removeObject(forKey: subscriber)
            if (subs.count == 0) {
                subscribers.removeObject(forKey: entity.id as NSString)
            }
        }
    }
}

struct DHDatahub {
    private let innerStorage = MemoryInnerStorage()
    
    func register<F: DHRemoteFacade>(_ facade: F) -> Void {
        innerStorage.registerFacade(facade)
    }
    
    func dataUpdated<E: DHEntity>(_ entity: E, _ data: E.OPS.Dt) -> Void {
        innerStorage.getSubscribers(entity.id).forEach { sendChangeToOne(entity, $0, data) }
    }
//    func dataUpdated<E: DHEntity>(_ entity: E, _ data: E.OPS.Dt) -> Void {
//        subscriber.onUpdate(relation: entity, relationData: data)
//    }
    
    func syncRelationClocks(_ subscriber: DHSubscriber, _ relationClocks: [DHEntityGenH : Any]) -> Void {
        relationClocks.forEach {
            let (relation, clock) = $0
            if let f = innerStorage.facade(relation.gen) {
                syncData(entityFacade: f, entity: relation.gen, subscriber, clock)
            }
        }
    }
//    func syncRelationClocks(_ subscriber: DHSubscriber, _ relationClocks: [DHEntityGenH : Any]) -> Void {
//        relationClocks.forEach {
//            let (relation, clock) = $0
//            syncData(entity: relation.gen, subscriber: subscriber, lastKnownDataClockOpt: clock)
//        }
//    }
    
    func sendChangeToOne<E: DHEntity>(_ entity: E, _ subscriber: DHSubscriber, _ entityData: E.OPS.Dt) -> Void {
        subscriber.onUpdate(entity, entityData)
    }
    
    func subscribe(_ entity: DHEntityGen, _ subscriber: DHSubscriber, _ lastKnownDataClock: Any) -> Bool {
        innerStorage.addSubscriber(entity.id, subscriber)

        let res: Void? = innerStorage.facade(entity).map {
            $0.onSubscribe(entity: entity, subscriber: subscriber, lastKnownDataClock: lastKnownDataClock)
            syncData(entityFacade: $0, entity: entity, subscriber, lastKnownDataClock)
        }
        return res == nil
    }
//    func subscribe(_ entity: DHEntityGen, _ lastKnownDataClock: Any) -> Bool {
//        remoteFacade.onSubscribe(entity: entity, subscriber: subscriber, lastKnownDataClock: lastKnownDataClock)
//        syncData(entity: entity, subscriber: subscriber, lastKnownDataClockOpt: lastKnownDataClock)
//        return true
//    }
    
    func syncData(entityFacade: DHRemoteFacade,
                  entity: DHEntityGen,
                  _ subscriber: DHSubscriber,
                  _ lastKnownDataClockOpt: Any?
                 ) -> Void {
        let lastKnownDataClock = lastKnownDataClockOpt ?? entityFacade.ops.genZero.genClock
        entityFacade.syncData(entityId: entity.id, dataClock: lastKnownDataClock)
    }
//    func syncData(entity: DHEntityGen,
//                  subscriber: DHSubscriber,
//                  lastKnownDataClockOpt: Any?) -> Void {
//        let lastKnownDataClock = lastKnownDataClockOpt ?? remoteFacade.ops.genZero.genClock
//        remoteFacade.syncData(entityId: entity.id, dataClock: lastKnownDataClock)
//    }
    
    func unsubscribe(_ entity: DHEntityGen, _ subscriber: DHSubscriber) -> Void {
        innerStorage.removeSubscriber(entity, subscriber)
    }
//    func unsubscribe(entity: DHEntityGen) -> Void {
//        remoteFacade.onUnsubscribe(entity: entity, subscriber: subscriber)
//    }
}

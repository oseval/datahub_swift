struct DHSubsData: DHData {
    typealias D = SetData<(DHEntityGen, Any)> /** entityId / clock **/
    typealias C = Int64
    
    let data: D
    let clock: Int64
    
    lazy var elemMap: [DHEntityGenH : Any] = {
        var m = [DHEntityGenH : Any]()
        self.data.elements.forEach { m.updateValue($0.1, forKey: DHEntityGenH(gen: $0.0)) }
        return m
    }()
    
    init(data: D = SetData(), clock: Int64 = 0) {
        self.data = data
        self.clock = clock
    }
}

class DHSubsDataOpsSimple: DHDataOps {
    typealias Dt = DHSubsData
    
    var kind: String { get { return "subscription" } }
    var gt: (Int64, Int64) -> Bool = { $0 > $1 }
    static var zero: Dt { get { return DHSubsData() } }
    
    func nextClock(_ current: Int64) -> Int64 {
        return Int64(NSDate().timeIntervalSince1970 * 1000)
    }
}

class DHSubsDataOps: ALODataOps<DHSubsDataOpsSimple> {
    static let o: DHSubsDataOps = DHSubsDataOps(ops: DHSubsDataOpsSimple())
}

protocol SubscriptionStorage {
    /**
     * Compose data with a given update and persist it to storage
     * @param data
     */
    func onUpdate(update: DHSubsData) -> Void
    
    /**
     * Load data from storage. Should return SubsOps.zero if none.
     * @return
     */
    func loadData(callback: (DHSubsData) -> Void) -> Void
}

class DHSubscriptionStorage {
    /**
     * Compose data with a given update and persist it to storage
     */
    func onUpdate(update: DHSubsData) ->  Void {
        
    }
    
    /**
     * Load data from storage. Should return SubsOps.zero if none.
     */
    func loadData(callback: (DHSubsData) -> Void) -> Void {
        
    }
}

class DHRemoteFacade {
    let ops: DHDataOpsGen
    let datahub: DHDatahub
    
    /**
     * Storage to save data in case of local datahub accidentally crashed.
     * Doesn't require any saving guarantees or transactions
     */
    let subscriptionStorage: DHSubscriptionStorage
    
    /**
     * Current subscriptions
     */
    private var subscriptions: ALOData<DHSubsData>
    
    init(ops: DHDataOpsGen, datahub: DHDatahub, subscriptionStorage: DHSubscriptionStorage) {
        self.ops = ops
        self.datahub = datahub
        
        self.subscriptionStorage = subscriptionStorage
        
        self.subscriptions = DHSubsDataOps.o.zero
    }
    
    func onSubscriptionsLoaded(subs: ALOData<DHSubsData>) -> Void {
        subscriptions = DHSubsDataOps.o.combine(self.subscriptions, subs)
    }
    
    /**
     * Calls by facade when subscriptions are updated, to send diff to RemoteSubscriber
     */
    func updateSubscriptions(update: ALOData<DHSubsData>) -> Void {
    }
    
    /**
     * Calls from remote to sync subscriptions
     */
    func syncSubscriptions(clock: Int64) -> Void {
        // subscriptions are always isSolid
        let diff = (try? DHSubsDataOps.o.diffFromClock(a: self.subscriptions, from: clock)) ?? self.subscriptions
        updateSubscriptions(update: diff)
    }
    
    func onSubscribe(entity: DHEntityGen, subscriber: DHSubscriber, lastKnownDataClock: Any) -> Void {
        let newClock = timestamp()
        let updatedSubs = self.subscriptions.data.data.add(el: (entity, lastKnownDataClock), newClock: newClock)
        let newData = self.subscriptions.updated(updated: DHSubsData(data: updatedSubs, clock: newClock))
        
        let diff = (try? DHSubsDataOps.o.diffFromClock(a: newData, from: self.subscriptions.clock)) ?? newData
        updateSubscriptions(update: diff)
        subscriptionStorage.onUpdate(update: newData.data)
        
        self.subscriptions = newData
    }
    
    func onUnsubscribe(entity: DHEntityGen, subscriber: DHSubscriber) -> Void {
        var dt = self.subscriptions.data
        dt.elemMap[DHEntityGenH(gen: entity)].map { relationClk in
            let newClock = timestamp()
            let updatedSubs = dt.data.remove(el: (entity, relationClk), newClock: newClock)
            let newData = self.subscriptions.updated(updated: DHSubsData(data: updatedSubs, clock: newClock))
    
            let diff = (try? DHSubsDataOps.o.diffFromClock(a: newData, from: self.subscriptions.clock)) ?? newData
            updateSubscriptions(update: diff)
            subscriptionStorage.onUpdate(update: newData.data)
    
            self.subscriptions = newData
        }
    }

    /**
     * Calls by external connection when data update comes from remote
     */
    func onUpdate<E: DHEntity>(entity: E, data: E.OPS.Dt) -> Void {
        datahub.dataUpdated(entity, data)
    }
    
    /**
     * Request explicit data difference from entity to force data syncing
     * Facade should sync data with remote (from a given clock) as reaction on call of this method
     * In other case data will be synced only after next data update
     */
    func syncData(entityId: String, dataClock: Any) -> Void {
        // Get difference explicitly
    }
}

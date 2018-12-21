//
//  HealthKitClient.swift
//
//  Created by Pérsio on 25/07/18.
//  Copyright © 2018 Persio Vieira. All rights reserved.
//

import HealthKit

enum HealthKitClientError: Error {
    case healthDataUnavailable
    case authorizationError(error: Error)
    case unauthorized
    case authorizationPendingToReadType(type: HKSampleType)
    case authorizationPendingToShareType(type: HKSampleType)
    case notAuthorized(type: HKSampleType)
    case unhandledError(error: Error)
}

struct HealthKitClient {
    
    // MARK: - Typealiases
    
    typealias SearchCompletion = (() throws -> [HKQuantitySample]?) -> Void
    typealias StoreCompletion = (() throws -> HKQuantitySample) -> Void
    typealias UpdateCompletion = (() throws -> Bool) -> Void
    typealias DeleteCompletion = (() throws -> Bool) -> Void
    typealias AuthorizationRequestCompletion = (() throws -> Void) -> Void
    
    // MARK: - Availability checking
    
    /// Returns Health app data availability
    static var isHealthDataAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    // MARK: - Authorization request
    
    /// Requests authorization to share and/or to read the types passed
    ///
    /// - Parameters:
    ///   - typesToShare: A Set containing the types to share
    ///   - typesToRead: A Set containing the types to read
    ///   - completion: An encapsulated throwable closure
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, toRead typesToRead: Set<HKSampleType>?, completion: @escaping AuthorizationRequestCompletion) {
        store.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            guard let error = error else {
                return completion {
                    if !success { throw HealthKitClientError.unauthorized }
                }
            }
            completion { throw HealthKitClientError.authorizationError(error: error) }
        }
    }
    
    // MARK: - CRUD operations
    
    /// Searchs for samples of the specified type
    ///
    /// - Parameters:
    ///   - type: The type of the samples do be searched
    ///   - predicate: An optional predicate to accurate the search
    ///   - limit: Specify the maximum results to be returned (0 means no limit)
    ///   - sortDescriptors: An optional sort descriptor to order de results
    ///   - completion: An encapsulated throwable closure
    func searchForQuantitySamplesOfType(_ type: HKQuantityType, predicate: NSPredicate?, limit: Int, sortDescriptors: [NSSortDescriptor]?, completion: @escaping SearchCompletion) {
        if HKHealthStore.isHealthDataAvailable() {
            switch store.authorizationStatus(for: type) {
            case .notDetermined:
                completion { throw HealthKitClientError.authorizationPendingToReadType(type: type) }
            default:
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { (_, samples, error) in
                    guard let error = error else {
                        guard let results = samples else { return completion { return nil } }
                        return completion { return results.map({ $0 as! HKQuantitySample }) }
                    }
                    completion { throw HealthKitClientError.unhandledError(error: error) }
                }
                self.store.execute(query)
            }
        } else {
            completion { throw HealthKitClientError.healthDataUnavailable }
        }
    }
    
    /// Stores a new sample
    ///
    /// - Parameters:
    ///   - sample: The sample to be stored
    ///   - completion: An encapsulated throwable closure
    func storeQuantitySample(_ sample: HKQuantitySample, completion: @escaping StoreCompletion) {
        if HKHealthStore.isHealthDataAvailable() {
            let authorization = store.authorizationStatus(for: sample.quantityType)
            switch authorization {
            case .sharingAuthorized:
                store.save(sample, withCompletion: { (_, error) in
                    guard let error = error else { return completion { return sample } }
                    completion { throw HealthKitClientError.unhandledError(error: error) }
                })
            case .sharingDenied:
                completion { throw HealthKitClientError.notAuthorized(type: sample.quantityType) }
            case .notDetermined:
                completion { throw HealthKitClientError.authorizationPendingToShareType(type: sample.quantityType) }
            }
        } else {
            completion { throw HealthKitClientError.healthDataUnavailable }
        }
    }
    
    /// Updates a specific sample
    ///
    /// - Parameters:
    ///   - sample: The sample to be updated
    ///   - completion: An encapsulated throwable closure
    func updateQuantitySample(_ sample: HKQuantitySample, completion: @escaping UpdateCompletion) {
        let predicate = NSPredicate(format: "startDate == %@ AND endDate == %@", argumentArray: [sample.startDate, sample.endDate])
        searchForQuantitySamplesOfType(sample.quantityType, predicate: predicate, limit: 1, sortDescriptors: nil) { (results) in
            do {
                let samples = try results()
                guard let sampleToDelete = samples?.first else { return completion { return false } }
                self.deleteQuantitySample(sampleToDelete, completion: { (success) in
                    do {
                        let success = try success()
                        if success {
                            self.store.save(sample, withCompletion: { (success, error) in
                                completion { return success && error == nil }
                            })
                        } else {
                            completion { return false }
                        }
                    } catch {
                        completion { throw HealthKitClientError.unhandledError(error: error) }
                    }
                })
            } catch {
                completion { throw HealthKitClientError.unhandledError(error: error) }
            }
        }
    }
    
    /// Deletes a specific sample
    ///
    /// - Parameters:
    ///   - sample: The sample to be deleted
    ///   - completion: An encapsulated throwable closure
    func deleteQuantitySample(_ sample: HKQuantitySample, completion: @escaping DeleteCompletion) {
        let predicate = NSPredicate(format: "startDate == %@ AND endDate == %@", argumentArray: [sample.startDate, sample.endDate])
        searchForQuantitySamplesOfType(sample.quantityType, predicate: predicate, limit: 1, sortDescriptors: nil) { (results) in
            do {
                let samples = try results()
                guard let sampleToDelete = samples?.first else { return completion { return false } }
                self.store.delete(sampleToDelete, withCompletion: { (success, error) in
                    completion { return success && error == nil }
                })
            } catch {
                completion { throw HealthKitClientError.unhandledError(error: error) }
            }
        }
    }
    
    // MARK: - Private statements
    
    private let store = HKHealthStore()
}

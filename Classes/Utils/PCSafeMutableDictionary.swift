//
//  PCSafeMutableDictionary.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 线程安全的可变字典
/// 
/// 注意：访问性能低于 NSMutableDictionary，但提供线程安全保证
/// 警告：快速枚举和枚举器不是线程安全的
class PCSafeMutableDictionary<Key: Hashable, Value>: NSMutableDictionary {
    private var _dic: NSMutableDictionary
    private let _lock = NSRecursiveLock()
    
    // MARK: - Initialization
    
    override init() {
        _dic = NSMutableDictionary()
        super.init()
    }
    
    required init?(coder: NSCoder) {
        _dic = NSMutableDictionary()
        super.init(coder: coder)
    }
    
    init(objects: [Any], forKeys keys: [NSCopying]) {
        _dic = NSMutableDictionary(objects: objects, forKeys: keys)
        super.init()
    }
    
    override init(capacity: Int) {
        _dic = NSMutableDictionary(capacity: capacity)
        super.init()
    }
    
    init(dictionary: [AnyHashable: Any]) {
        _dic = NSMutableDictionary(dictionary: dictionary)
        super.init()
    }
    
    init(dictionary: [AnyHashable: Any], copyItems: Bool) {
        _dic = NSMutableDictionary(dictionary: dictionary, copyItems: copyItems)
        super.init()
    }
    
    // MARK: - NSDictionary Methods
    
    override var count: Int {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.count
    }
    
    override func object(forKey aKey: Any) -> Any? {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.object(forKey: aKey)
    }
    
    override func keyEnumerator() -> NSEnumerator {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.keyEnumerator()
    }
    
    override var allKeys: [Any] {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.allKeys
    }
    
    override func allKeys(for anObject: Any) -> [Any] {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.allKeys(for: anObject)
    }
    
    override var allValues: [Any] {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.allValues
    }
    
    override func objectEnumerator() -> NSEnumerator {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.objectEnumerator()
    }
    
    override func objects(forKeys keys: [Any], notFoundMarker marker: Any) -> [Any] {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.objects(forKeys: keys, notFoundMarker: marker)
    }
    
    override func keysSortedByValue(comparator cmptr: Comparator) -> [Any] {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.keysSortedByValue(comparator: cmptr)
    }
    
    override func enumerateKeysAndObjects(_ block: (Any, Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.enumerateKeysAndObjects(block)
    }
    
    override func enumerateKeysAndObjects(options opts: NSEnumerationOptions = [], using block: (Any, Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.enumerateKeysAndObjects(options: opts, using: block)
    }
    
    override func keysOfEntries(passingTest predicate: (Any, Any, UnsafeMutablePointer<ObjCBool>) -> Bool) -> Set<AnyHashable> {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.keysOfEntries(passingTest: predicate)
    }
    
    override func keysOfEntries(options opts: NSEnumerationOptions = [], passingTest predicate: (Any, Any, UnsafeMutablePointer<ObjCBool>) -> Bool) -> Set<AnyHashable> {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.keysOfEntries(options: opts, passingTest: predicate)
    }
    
    // MARK: - NSMutableDictionary Methods
    
    override func removeObject(forKey aKey: Any) {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.removeObject(forKey: aKey)
    }
    
    override func setObject(_ anObject: Any, forKey aKey: NSCopying) {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.setObject(anObject, forKey: aKey)
    }
    
    override func addEntries(from otherDictionary: [AnyHashable: Any]) {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.addEntries(from: otherDictionary)
    }
    
    override func removeAllObjects() {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.removeAllObjects()
    }
    
    override func removeObjects(forKeys keyArray: [Any]) {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.removeObjects(forKeys: keyArray)
    }
    
    override func setDictionary(_ otherDictionary: [AnyHashable: Any]) {
        _lock.lock()
        defer { _lock.unlock() }
        _dic.setDictionary(otherDictionary)
    }
    
    // MARK: - Subscript
    
//    subscript(key: Any) -> Any? {
//        get {
//            _lock.lock()
//            defer { _lock.unlock() }
//            return _dic[key]
//        }
//        set {
//            _lock.lock()
//            defer { _lock.unlock() }
//            if let newValue = newValue, let key = key as? NSCopying {
//                _dic[key] = newValue
//            } else if let key = key as? NSCopying {
//                _dic.removeObject(forKey: key)
//            }
//        }
//    }
    
    // MARK: - NSCopying
    
    override func copy(with zone: NSZone? = nil) -> Any {
        return mutableCopy(with: zone)
    }
    
    override func mutableCopy(with zone: NSZone? = nil) -> Any {
        _lock.lock()
        defer { _lock.unlock() }
        let copiedDictionary = PCSafeMutableDictionary<Key, Value>(dictionary: _dic as! [AnyHashable: Any])
        return copiedDictionary
    }
    
    // MARK: - NSFastEnumeration
    
    override func countByEnumerating(with state: UnsafeMutablePointer<NSFastEnumerationState>, objects stackbuf: AutoreleasingUnsafeMutablePointer<AnyObject?>, count len: Int) -> Int {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.countByEnumerating(with: state, objects: stackbuf, count: len)
    }
    
    // MARK: - Equality
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object else { return false }
        if object as AnyObject === self {
            return true
        }
        
        guard let other = object as? PCSafeMutableDictionary<Key, Value> else {
            return false
        }
        
        _lock.lock()
        other._lock.lock()
        defer {
            other._lock.unlock()
            _lock.unlock()
        }
        return _dic.isEqual(other._dic)
    }
    
    override var hash: Int {
        _lock.lock()
        defer { _lock.unlock() }
        return _dic.hash
    }
}


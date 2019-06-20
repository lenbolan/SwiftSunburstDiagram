//
//  Model.swift
//  SunburstDiagram
//
//  Created by Ludovic Landry on 6/10/19.
//  Copyright © 2019 Ludovic Landry. All rights reserved.
//

import Combine
import SwiftUI

class Sunburst: BindableObject {

    struct Arc: Equatable, Identifiable {
        var id: ObjectIdentifier
        
        var width: Double
        var backgroundColor: Color
        var isTextHidden: Bool
        
        let text: String
        let image: UIImage?
        
        fileprivate(set) var childArcs: [Arc]?
        
        // The start location of the arc, as an angle in radians.
        fileprivate(set) var start = 0.0
        // The end location of the arc, as an angle in radians.
        fileprivate(set) var end = 0.0
        
        init(text: String, image: UIImage? = nil, width: Double, backgroundColor: UIColor, childArcs: [Arc]? = nil, isTextHidden: Bool = false) {
            self.id = ObjectIdentifier(text as NSString)
            
            self.width = width
            let ciColor = CIColor(color: backgroundColor) // All this is far from ideal :(
            self.backgroundColor = Color(red: Double(ciColor.red), green: Double(ciColor.green), blue: Double(ciColor.blue))
            self.isTextHidden = isTextHidden
            
            self.childArcs = childArcs
            
            self.image = image
            self.text = text
        }
    }
    
    private(set) var arcs: [Arc] = []
    let configuration: SunburstConfiguration
    
    // Trivial publisher for our changes.
    let didChange = PassthroughSubject<Sunburst, Never>()

    init(configuration: SunburstConfiguration) {
        self.configuration = configuration

        configuration.validateAndPrepare()
        _ = configuration.didChange.sink { [weak self] (config) in
            self?.modelDidChange()
        }

        modelDidChange()
    }
    
    // Non-zero while a batch of updates is being processed.
    private var nestedUpdates = 0
    
    // Invokes `body()` such that any changes it makes to the model
    // will only post a single notification to observers.
    func batch(_ body: () -> Void) {
        nestedUpdates += 1
        defer {
            nestedUpdates -= 1
            if nestedUpdates == 0 {
                modelDidChange()
            }
        }
        body()
    }
    
    // MARK: Private
    
    private func configureArcs(nodes: [Node], totalValue: Double) -> [Sunburst.Arc] {
        var arcs: [Sunburst.Arc] = []
        
        // Sort the nodes if needed
        let orderedNodes: [Node]
        switch configuration.nodesSort {
        case .asc:
            orderedNodes = nodes.sorted { $0.computedValue == $1.computedValue ? ($0.value ?? 0) < ($1.value ?? 0) : $0.computedValue < $1.computedValue }
        case .desc:
            orderedNodes = nodes.sorted { $0.computedValue == $1.computedValue ? ($0.value ?? 0) > ($1.value ?? 0) : $0.computedValue > $1.computedValue }
        case .none:
            orderedNodes = nodes
        }
        
        // Iterate through the nodes
        for node in orderedNodes {
            var arc = Sunburst.Arc.configureWith(node: node, totalValue: totalValue)
            if let children = node.children {
                arc.childArcs = configureArcs(nodes: children, totalValue: totalValue)
            }
            arcs.append(arc)
        }
        return arcs
    }
    
    // Called after each change, updates derived model values and posts the notification.
    private func modelDidChange() {
        guard nestedUpdates == 0 else { return }

        arcs = configureArcs(nodes: configuration.nodes, totalValue: configuration.totalNodesValue)

        // Recalculate locations, to pack within circle.
        let startLocation = -.pi / 2.0 + (configuration.startingAngle * .pi / 180)
        recalculateLocations(arcs: &arcs, startLocation: startLocation)
        
        didChange.send(self)
    }
    
    private func recalculateLocations(arcs: inout [Sunburst.Arc], startLocation location: Double) {
        var location = location
        for index in 0 ..< arcs.count {
            if arcs[index].childArcs != nil {
                recalculateLocations(arcs: &arcs[index].childArcs!, startLocation: location)
            }
            arcs[index].start = location
            location += arcs[index].width
            arcs[index].end = location
        }
    }
}

// MARK: - Arc

extension Sunburst.Arc {
    
    static func configureWith(node: Node, totalValue: Double) -> Sunburst.Arc {
        let width = (node.computedValue / totalValue) * 2.0 * .pi
        return Sunburst.Arc(text: node.name, image: node.image, width: width,
                            backgroundColor: node.computedBackgroundColor, isTextHidden: !node.showName)
    }
}

// MARK: - Animation

// Extend the arc description to conform to the Animatable type to
// simplify creation of custom shapes using the arc.
extension Sunburst.Arc: Animatable {
    // Use a composition of pairs to merge the interpolated values into
    // a single type. AnimatablePair acts as a single interpolatable
    // values, given two interpolatable input types. We'll interpolate
    // the derived start/end angles.
    
    public typealias AnimatableData = AnimatablePair<Double, Double>
    
    public var animatableData: AnimatableData {
        get {
            AnimatablePair(start, end)
        }
        set {
            start = newValue.first
            end = newValue.second
        }
    }
}

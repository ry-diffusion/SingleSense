import Foundation

/// Publishes observable state on the next run-loop turn.
///
/// The lightbar tick and the permission poll are both run-loop timers in
/// `.common` mode, so they keep firing during event tracking — including while
/// SwiftUI is recomputing a view because the user is dragging a slider.
/// Mutating `@Published` state at that moment is undefined behaviour, and is
/// what SwiftUI reports as "Publishing changes from within view updates".
///
/// Hopping to the next turn puts the mutation safely outside any update in
/// progress. Hardware writes deliberately do *not* go through here: they carry
/// no observable state and the lightbar should not lag a frame behind.
@inline(__always)
func publishOnNextRunLoopTurn(_ work: @escaping () -> Void) {
    DispatchQueue.main.async(execute: work)
}

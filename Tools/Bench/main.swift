import Foundation

func rackSim(_ rules: Rules) -> Simulation {
    var balls = [Ball(kind: .cue(player: 0), pos: Table.headSpot)]
    for (n, p) in Table.rack(for: rules) { balls.append(Ball(kind: .object(number: n), pos: p)) }
    return Simulation(balls: balls)
}

func time(_ label: String, _ iterations: Int, _ body: () -> Void) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations { body() }
    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    print(String(format: "%-46@ %8.3f ms/call   (%d calls)", label as NSString, dt / Double(iterations), iterations))
}

let sim = rackSim(.potPoints)
// Straight at the rack (contact, then follow-through).
let straight = Vec(1, 0) * 170
// Slightly off: glancing hit.
let glance = Vec(1, 0.06).normalized * 170
// Away from the rack: bounces off cushions, never touches a ball (worst case).
let away = Vec(-0.5, 1).normalized * 170
let weak = Vec(1, 0.3).normalized * 40
// Cue moving along a cushion with nothing to hit.
let rail = Vec(0.2, -1).normalized * 170

var sink = 0
time("preview: straight at rack, full power", 200) { sink &+= ShotPreview.make(in: sim, cue: 0, pull: straight).cue.count }
time("preview: glancing hit", 200) { sink &+= ShotPreview.make(in: sim, cue: 0, pull: glance).cue.count }
time("preview: miss everything (cushions, worst)", 200) { sink &+= ShotPreview.make(in: sim, cue: 0, pull: away).cue.count }
time("preview: weak shot", 200) { sink &+= ShotPreview.make(in: sim, cue: 0, pull: weak).cue.count }
time("preview: along the rail", 200) { sink &+= ShotPreview.make(in: sim, cue: 0, pull: rail).cue.count }

// Full break, every ball moving: the main game loop cost per 1/60 s frame (4 steps).
var broke = sim
broke.launch(0, velocity: Vec(1900, 0))
var events: [SimEvent] = []
var steps = 0
let t0 = DispatchTime.now().uptimeNanoseconds
while broke.isMoving && steps < 240 * 20 { broke.step(events: &events); events.removeAll(keepingCapacity: true); steps += 1 }
let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
print(String(format: "break settle: %d steps in %.2f ms -> %.4f ms/step -> %.3f ms per 60fps frame while moving", steps, dt, dt / Double(steps), dt / Double(steps) * 4))
print("sink \(sink)")

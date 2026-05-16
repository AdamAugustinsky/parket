import Dispatch

fputs("running pane tests...\n", stderr)
let (p0, f0) = PaneTests.runAll()

fputs("running tiler tests...\n", stderr)
let (p1, f1) = TilerTests.runAll()

fputs("running performance tests...\n", stderr)
let (p2, f2) = TilerPerformanceTests.runAll()

let passed = p0 + p1 + p2
let failed = f0 + f1 + f2

fputs("\n\(passed) passed, \(failed) failed\n", stderr)

if failed > 0 {
    exit(1)
}

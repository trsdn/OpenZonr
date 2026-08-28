import Foundation
import OpenZonrMac

// The whole tool is in OpenZonrMac. This target exists so that `swift run
// openzonr` keeps working during development without building or signing a
// bundle — the shipped command line is the app's own binary, which is the one
// the Accessibility grant belongs to.
OpenZonrCommandLine.run(Array(CommandLine.arguments.dropFirst()))

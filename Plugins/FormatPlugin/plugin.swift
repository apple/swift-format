import PackagePlugin
import Foundation

@main
struct FormatPlugin {
  func format(tool: PluginContext.Tool, targetDirectories: [String], configurationFilePath: String?) throws {
    let swiftFormatExec = URL(fileURLWithPath: tool.path.string)
    
    var arguments: [String] = ["format"]
    
    arguments.append(contentsOf: targetDirectories)
    
    arguments.append(contentsOf: ["--recursive", "--parallel", "--in-place"])
    
    if let configurationFilePath = configurationFilePath {
      arguments.append(contentsOf: ["--configuration", configurationFilePath])
    }
    
    let process = try Process.run(swiftFormatExec, arguments: arguments)
    process.waitUntilExit()
    
    if process.terminationReason == .exit && process.terminationStatus == 0 {
      Diagnostics.remark("Formatted the source code.")
    }
    else {
      let problem = "\(process.terminationReason):\(process.terminationStatus)"
      Diagnostics.error("swift-format invocation failed: \(problem)")
    }
  }
}

extension FormatPlugin: CommandPlugin {
  func performCommand(
    context: PluginContext,
    arguments: [String]
  ) async throws {
    let swiftFormatTool = try context.tool(named: "swift-format")

    var argExtractor = ArgumentExtractor(arguments)

    let configurationFilePath = argExtractor.extractOption(named: "swift-format-configuration").first

    let sourceCodeTargets = context.package.targets.compactMap{ $0 as? SourceModuleTarget }

    try format(
      tool: swiftFormatTool,
      targetDirectories: sourceCodeTargets.map(\.directory.string),
      configurationFilePath: configurationFilePath
    )
  }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension FormatPlugin: XcodeCommandPlugin {
  func performCommand(context: XcodeProjectPlugin.XcodePluginContext, arguments: [String]) throws {
    let swiftFormatTool = try context.tool(named: "swift-format")
    
    var argExtractor = ArgumentExtractor(arguments)
    let configurationFilePath = argExtractor.extractOption(named: "swift-format-configuration").first
    
    try format(
      tool: swiftFormatTool,
      targetDirectories: [context.xcodeProject.directory.string],
      configurationFilePath: configurationFilePath
    )
  }
}
#endif

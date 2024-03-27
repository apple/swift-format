import PackagePlugin
import Foundation

@main
struct LintBuildPlugin {
  static private let toolName = "swift-format"
  
  private func createBuildCommands(
    pluginWorkDirectory: Path,
    tool: PluginContext.Tool,
    targetDirectory: Path
  ) -> [Command] {
    let arguments = [
      "lint",
      targetDirectory.string,
      "--recursive",
      "--parallel",
      "--strict",
      "--configuration",
      targetDirectory.appending(subpath: ".swift-format").string
    ]
    
    return [
      .prebuildCommand(
        displayName: "Lint Source Code",
        executable: tool.path,
        arguments: arguments,
        environment: [:],
        outputFilesDirectory: pluginWorkDirectory.appending(Self.toolName)
      )
    ]
  }
}

extension LintBuildPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PackagePlugin.PluginContext,
    target: PackagePlugin.Target
  ) async throws -> [PackagePlugin.Command] {
    createBuildCommands(
      pluginWorkDirectory: context.pluginWorkDirectory,
      tool: try context.tool(named: Self.toolName),
      targetDirectory: target.directory
    )
  }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension LintBuildPlugin: XcodeBuildToolPlugin {
  func createBuildCommands(
    context: XcodeProjectPlugin.XcodePluginContext,
    target: XcodeProjectPlugin.XcodeTarget
  ) throws -> [PackagePlugin.Command] {
    createBuildCommands(
      pluginWorkDirectory: context.pluginWorkDirectory,
      tool: try context.tool(named: Self.toolName),
      targetDirectory: context.xcodeProject.directory
    )
  }
}
#endif

public class ExtensionDeclTests: PrettyPrintTestCase {
  public func testBasicExtensionDeclarations() {
    let input =
      """
      extension MyExtension {
        let A: Int
        let B: Bool
      }
      public extension MyExtension {
        let A: Int
        let B: Bool
      }
      public extension MyLongerExtension {
        let A: Int
        let B: Bool
      }
      """

    let expected =
      """
      extension MyExtension {
        let A: Int
        let B: Bool
      }
      public extension MyExtension {
        let A: Int
        let B: Bool
      }
      public extension
        MyLongerExtension
      {
        let A: Int
        let B: Bool
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 33)
  }

  public func testExtensionInheritence() {
    let input =
      """
      extension MyExtension: ProtoOne {
        let A: Int
        let B: Bool
      }
      extension MyExtension: ProtoOne, ProtoTwo {
        let A: Int
        let B: Bool
      }
      extension MyExtension: ProtoOne, ProtoTwo, ProtoThree {
        let A: Int
        let B: Bool
      }
      """

    let expected =
      """
      extension MyExtension: ProtoOne {
        let A: Int
        let B: Bool
      }
      extension MyExtension: ProtoOne, ProtoTwo {
        let A: Int
        let B: Bool
      }
      extension MyExtension: ProtoOne, ProtoTwo,
        ProtoThree
      {
        let A: Int
        let B: Bool
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50)
  }

  public func testExtensionWhereClause() {
    let input =
      """
      extension MyExtension where S: Collection {
        let A: Int
        let B: Double
      }
      extension MyExtension where S: Collection, T: ReallyLongExtensionName {
        let A: Int
        let B: Double
      }
      extension MyExtension where S: Collection, T: ReallyLongExtensionName, U: AnotherLongExtension {
        let A: Int
        let B: Double
      }
      """

    let expected =
      """
      extension MyExtension where S: Collection {
        let A: Int
        let B: Double
      }
      extension MyExtension
        where S: Collection, T: ReallyLongExtensionName
      {
        let A: Int
        let B: Double
      }
      extension MyExtension
        where S: Collection, T: ReallyLongExtensionName,
          U: AnotherLongExtension
      {
        let A: Int
        let B: Double
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 70)
  }

  public func testExtensionWhereClauseWithInheritence() {
    let input =
      """
      extension MyExtension: ProtoOne where S: Collection {
        let A: Int
        let B: Double
      }
      extension MyExtension: ProtoOne, ProtoTwo where S: Collection, T: Protocol {
        let A: Int
        let B: Double
      }
      """

    let expected =
      """
      extension MyExtension: ProtoOne where S: Collection {
        let A: Int
        let B: Double
      }
      extension MyExtension: ProtoOne, ProtoTwo
        where S: Collection, T: Protocol
      {
        let A: Int
        let B: Double
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 70)
  }

  public func testExtensionAttributes() {
    let input =
      """
      @dynamicMemberLookup public extension MyExtension {
        let A: Int
        let B: Double
      }
      @dynamicMemberLookup @objc public extension MyExtension {
        let A: Int
        let B: Double
      }
      @dynamicMemberLookup @objc @objcMembers public extension MyExtension {
        let A: Int
        let B: Double
      }
      @dynamicMemberLookup
      @available(swift 4.0)
      public extension MyExtension {
        let A: Int
        let B: Double
      }
      """

    let expected =
      """
      @dynamicMemberLookup public extension MyExtension {
        let A: Int
        let B: Double
      }
      @dynamicMemberLookup @objc public extension MyExtension {
        let A: Int
        let B: Double
      }
      @dynamicMemberLookup @objc @objcMembers
      public extension MyExtension {
        let A: Int
        let B: Double
      }
      @dynamicMemberLookup
      @available(swift 4.0)
      public extension MyExtension {
        let A: Int
        let B: Double
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 60)
  }

  public func testExtensionFullWrap() {
    let input =
      """
      public extension MyContainer: MyContainerProtocolOne, MyContainerProtocolTwo, SomeoneElsesContainerProtocol, SomeFrameworkContainerProtocol where BaseCollection: Collection, BaseCollection.Element: Equatable, BaseCollection.Element: SomeOtherProtocol {
        let A: Int
        let B: Double
      }
      """

    let expected =

      """
      public extension MyContainer: MyContainerProtocolOne,
        MyContainerProtocolTwo,
        SomeoneElsesContainerProtocol,
        SomeFrameworkContainerProtocol
        where BaseCollection: Collection,
          BaseCollection.Element: Equatable,
          BaseCollection.Element: SomeOtherProtocol
      {
        let A: Int
        let B: Double
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50)
  }

  public func testEmptyExtension() {
    let input = "extension Foo {}"
    assertPrettyPrintEqual(input: input, expected: input + "\n", linelength: 50)

    let wrapped = """
      extension Foo {
      }

      """
    assertPrettyPrintEqual(input: input, expected: wrapped, linelength: 15)
  }

  public func testEmptyExtensionWithComment() {
    let input = """
      extension Foo {
        // foo
      }
      """
    assertPrettyPrintEqual(input: input, expected: input + "\n", linelength: 50)
  }

  public func testOneMemberExtension() {
    let input = "extension Foo { var bar: Int { return 0 } }"
    assertPrettyPrintEqual(input: input, expected: input + "\n", linelength: 50)
  }
}

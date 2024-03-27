import SwiftFormat
import XCTest

final class Selections: PrettyPrintTestCase {
  func testSelectAll() {
    let input =
      """
      ➡️func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
        // do stuff
      }
      }⬅️
      """

    let expected =
      """
      func foo() {
        if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
          // do stuff
        }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }

  func testSelectComment() {
    let input =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      ➡️// do stuff⬅️
      }
      }
      """

    let expected =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
          // do stuff
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }

  func testInsertionPointBeforeComment() {
    let input =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      ➡️⬅️// do stuff
      }
      }
      """

    let expected =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
          // do stuff
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }

  func testSpacesInline() {
    let input =
      """
      func foo() {
      if let SomeReallyLongVar ➡️ =   ⬅️Some.More.Stuff(), let a = myfunc() {
      // do stuff
      }
      }
      """

    let expected =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      // do stuff
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }

  func testSpacesFullLine() {
    // FIXME: we should be able to set the end range to _after_ the opening brace.
    //   Currently, this also indents the comment line. Also, it would fail idempotency (since the
    //   tests don't update the selection, and it would no longer end after the brace)
    let input =
      """
      func foo() {
      ➡️if let SomeReallyLongVar  =   Some.More.Stuff(), let a = myfunc() ⬅️{
      // do stuff
      }
      }
      """

    let expected =
      """
      func foo() {
        if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      // do stuff
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }

  func testWrapInline() {
    let input =
      """
      func foo() {
      if let SomeReallyLongVar = ➡️Some.More.Stuff(), let a = myfunc()⬅️ {
      // do stuff
      }
      }
      """

    let expected =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More
          .Stuff(), let a = myfunc() {
      // do stuff
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 44)
  }

  func testCommentsOnly() {
    let input =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      ➡️// do stuff
      // do more stuff⬅️
      var i = 0
      }
      }
      """

    let expected =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
          // do stuff
          // do more stuff
      var i = 0
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }

  func testVarOnly() {
    let input =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      // do stuff
      // do more stuff
      ➡️⬅️var i = 0
      }
      }
      """

    let expected =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      // do stuff
      // do more stuff
          var i = 0
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }

  #if false
  func testFirstCommentAndVar() {
    let input =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
      ➡️⬅️// do stuff
      // do more stuff
      ➡️⬅️var i = 0
      }
      }
      """

    // FIXME: this shouldn't indent the second comment
    //    Also not idempotent since the selection doesn't get updated.
    let expected =
      """
      func foo() {
      if let SomeReallyLongVar = Some.More.Stuff(), let a = myfunc() {
          // do stuff
      // do more stuff
          var i = 0
      }
      }
      """

    // The line length ends on the last paren of .Stuff()
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80)
  }
  #endif
}

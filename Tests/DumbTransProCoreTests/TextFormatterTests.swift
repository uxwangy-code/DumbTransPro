import Testing
@testable import DumbTransProCore

struct TextFormatterTests {
    @Test func basicKebabCase() {
        #expect(TextFormatter.toKebabCase("hello world") == "hello-world")
    }

    @Test func uppercaseToLower() {
        #expect(TextFormatter.toKebabCase("Hello World") == "hello-world")
    }

    @Test func removePunctuation() {
        #expect(TextFormatter.toKebabCase("hello, world!") == "hello-world")
    }

    @Test func collapseSpaces() {
        #expect(TextFormatter.toKebabCase("hello   world") == "hello-world")
    }

    @Test func trimEdges() {
        #expect(TextFormatter.toKebabCase("  hello world  ") == "hello-world")
    }

    @Test func preserveNumbers() {
        #expect(TextFormatter.toKebabCase("project 2024") == "project-2024")
    }

    @Test func alreadyKebab() {
        #expect(TextFormatter.toKebabCase("already-kebab") == "already-kebab")
    }

    @Test func emptyString() {
        #expect(TextFormatter.toKebabCase("") == "")
    }

    @Test func chinesePassthrough() {
        #expect(TextFormatter.toKebabCase("good good study") == "good-good-study")
    }
}

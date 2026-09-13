import QtQuick
import QtTest
import "../linkify.js" as Links

TestCase {
    name: "MessageLinks"
    function test_escape_untrusted_markup() {
        const value = Links.render('<img src="file:///private"><b>hello</b>', "#00ff00");
        verify(!value.includes("<img"));
        verify(!value.includes("<b>"));
        verify(value.includes("&lt;img"));
    }
    function test_links_preserve_query_parameters() {
        const value = Links.render("https://example.org/?a=1&b=2", "#00ff00");
        verify(value.includes('href="https://example.org/?a=1&amp;b=2"'));
    }
    function test_sentence_punctuation_and_parentheses() {
        const value = Links.render("See (https://example.org/hello).", "#00ff00");
        verify(value.includes('href="https://example.org/hello"'));
        verify(value.endsWith("</a>)."));
        verify(Links.render("https://example.org/Hello_(world)", "#00ff00").includes('href="https://example.org/Hello_(world)"'));
    }
    function test_only_web_schemes_open() {
        verify(Links.isWebUrl("https://example.org"));
        verify(Links.isWebUrl("http://example.org"));
        verify(!Links.isWebUrl("javascript:alert(1)"));
        verify(!Links.isWebUrl("file:///private"));
        verify(!Links.isWebUrl("https://example.org\ncommand"));
    }
    function test_newlines_remain_visible() {
        compare(Links.render("one\ntwo", "#00ff00"), "one<br>two");
    }
}

import QtQuick
import QtTest
import "../emoji-data.js" as Emojis
TestCase {
    name: "EmojiCatalog"
    function includes(query, emoji) { return Emojis.search(query, -1).some(entry => entry[0] === emoji); }
    function test_catalog() {
        compare(Emojis.search("", -1).length, 3953);
        compare(new Set(Emojis.entries.map(entry => entry[0])).size, 3953);
        verify(includes("", "🫪")); // Emoji 17
        verify(includes("", "👨‍👩‍👧‍👦"));
        verify(includes("", "👍🏿"));
        verify(includes("", "🇦🇹"));
    }
    function test_search() {
        verify(includes("katze", "🐈"));
        verify(includes("cat", "🐈"));
        verify(includes("ÖSTERREICH", "🇦🇹"));
        verify(includes("daumen", "👍🏿"));
        verify(includes("dark skin", "👍🏿"));
        compare(Emojis.search("zzzz-no-match", -1).length, 0);
        compare(Emojis.search("   ", -1).length, 3953);
    }
    function test_categories_and_global_search() {
        const flags = Emojis.groups.indexOf("Flags");
        verify(Emojis.search("", flags).every(entry => entry[1] === flags));
        verify(Emojis.search("katze", flags).some(entry => entry[0] === "🐈"));
    }
}

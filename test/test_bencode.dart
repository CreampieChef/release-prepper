/// The parts a real torrent file is made of, so a fixture is built as the format
/// builds it: `d`, its entries, `e`. A dictionary is closed by the same rule, so a
/// fixture cannot be the reason a test fails for something it is not about.
///
/// It is here rather than in one test file because two of them need it: the reader
/// and the section that shows what it reads. A copy in each would be two fixtures
/// that can disagree.
String bencodeEntry(String key, String value) => '${key.length}:$key$value';

String bencodeDict(String entries) => 'd$entries$_e';

String bencodeInteger(int value) => 'i$value$_e';

const _e = 'e';

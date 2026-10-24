import unittest

from scripts.verify_lab import build_marker, event_contains_marker, marker_url


class VerifierHelpersTest(unittest.TestCase):
    def test_marker_is_unique_and_safe_for_query_strings(self):
        first = build_marker()
        second = build_marker()
        self.assertNotEqual(first, second)
        self.assertRegex(first, r"^fyndlab-[0-9a-f]{32}$")
        self.assertEqual(marker_url("http://10.42.1.10/", first), f"http://10.42.1.10?lab_marker={first}")

    def test_event_search_finds_marker_in_nested_wazuh_document(self):
        marker = "fyndlab-test-marker"
        event = {"_source": {"full_log": f'GET /?lab_marker={marker} HTTP/1.1'}}
        self.assertTrue(event_contains_marker(event, marker))
        self.assertFalse(event_contains_marker(event, "different-marker"))


if __name__ == "__main__":
    unittest.main()
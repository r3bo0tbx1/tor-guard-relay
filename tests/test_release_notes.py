"""Exercise release-note portability and broken-link publication failures offline."""
import importlib.util
from pathlib import Path
import subprocess as sp
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/release/render-release-notes.py'
spec = importlib.util.spec_from_file_location('release_notes', SCRIPT)
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)
from markdown_links import local_target


class ReleaseNoteLinksTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.document = self.root / 'docs/releases/v2.2.1.md'
        self.document.parent.mkdir(parents=True)
        (self.root / 'docs/BACKUP.md').write_text(
            '# Recovery\n## 🔐 Encrypted backup\n## 🔐 Encrypted backup\n<a id="explicit"></a>\n',
            encoding='utf-8')
        self.base = 'https://github.com/r3bo0tbx1/tor-guard-relay'
        self.pinned = f'{self.base}/blob/v2.2.1/docs/BACKUP.md'

    def render(self, text):
        self.document.write_text(text, encoding='utf-8')
        return notes.render(self.root, '2.2.1')

    def test_relative_link_becomes_absolute_and_tag_pinned(self):
        self.assertEqual(self.render('[Recovery](../BACKUP.md)'), f'[Recovery]({self.pinned})')

    def test_root_relative_github_main_and_head_links_are_pinned(self):
        for prefix in (self.base, '/r3bo0tbx1/tor-guard-relay'):
            for ref in ('main', 'HEAD'):
                with self.subTest(prefix=prefix, ref=ref):
                    self.assertEqual(self.render(f'[Recovery]({prefix}/blob/{ref}/docs/BACKUP.md)'),
                                     f'[Recovery]({self.pinned})')

    def test_current_tag_is_validated_without_creating_a_git_tag(self):
        value = f'[Recovery]({self.pinned}#-encrypted-backup)'
        self.assertEqual(self.render(value), value)

    def test_absolute_missing_file_blocks_publication(self):
        with self.assertRaisesRegex(ValueError, 'missing'):
            self.render(f'[Recovery]({self.base}/blob/v2.2.1/docs/missing.md)')

    def test_absolute_missing_anchor_blocks_publication(self):
        with self.assertRaisesRegex(ValueError, 'missing anchor'):
            self.render(f'[Recovery]({self.pinned}#outdated-heading)')

    def test_duplicate_emoji_headings_and_explicit_anchor(self):
        for anchor in ('-encrypted-backup', '-encrypted-backup-1', 'explicit'):
            with self.subTest(anchor=anchor):
                self.assertIn(f'{self.pinned}#{anchor}', self.render(f'[Recovery](../BACKUP.md#{anchor})'))

    def test_other_repositories_and_external_links_remain_unchanged(self):
        for url in ('https://example.org/missing.md',
                    'https://github.com/another/project/blob/main/docs/missing.md',
                    f'{self.base}-other/blob/main/docs/missing.md',
                    'https://github.com.example.org/r3bo0tbx1/tor-guard-relay/blob/main/missing.md'):
            value = f'[External]({url})'
            with self.subTest(url=url):
                self.assertEqual(self.render(value), value)

    def test_release_documentation_cannot_silently_point_at_wrong_ref(self):
        for ref in ('mian', 'v2.2.0'):
            with self.subTest(ref=ref), self.assertRaisesRegex(ValueError, 'must target v2.2.1'):
                self.render(f'[Recovery]({self.base}/blob/{ref}/docs/BACKUP.md)')

    def test_html_and_reference_style_links_are_pinned(self):
        self.assertEqual(self.render('<a href="../BACKUP.md">Recovery</a>'),
                         f'<a href="{self.pinned}">Recovery</a>')
        self.assertEqual(self.render('[Recovery][guide]\n\n[guide]: ../BACKUP.md "Guide"\n'),
                         f'[Recovery][guide]\n\n[guide]: {self.pinned} "Guide"\n')

    def test_fenced_examples_are_preserved_and_not_interpreted_as_links(self):
        for fence in ('```', '~~~~'):
            value = f'{fence}markdown\n[Example](../../../../missing.md)\n{fence}\n'
            with self.subTest(fence=fence):
                self.assertEqual(self.render(value), value)

    def test_release_body_navigation_remains_local(self):
        self.assertEqual(self.render('# Recovery\n[Back](#recovery)\n'), '# Recovery\n[Back](#recovery)\n')

    def test_relative_image_uses_tag_pinned_raw_content(self):
        (self.root / 'docs/cover.png').write_bytes(b'image fixture')
        self.assertEqual(self.render('![Cover](../cover.png)'),
                         '![Cover](https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/v2.2.1/docs/cover.png)')

    def test_raw_github_main_url_is_validated_and_pinned(self):
        value = 'https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/docs/BACKUP.md'
        self.assertEqual(self.render(f'[Recovery]({value})'),
                         f'[Recovery]({value.replace("/main/", "/v2.2.1/")})')

    def test_encoded_paths_and_link_titles_survive_rendering(self):
        (self.root / 'docs/Operator Guide.md').write_text('# Guide\n', encoding='utf-8')
        self.assertEqual(self.render('[Guide](<../Operator%20Guide.md#guide> "Read this")'),
                         f'[Guide](<{self.base}/blob/v2.2.1/docs/Operator%20Guide.md#guide> "Read this")')

    def test_query_and_fragment_survive_rendering(self):
        self.assertEqual(self.render('[Guide](../BACKUP.md?plain=1#recovery)'),
                         f'[Guide]({self.pinned}?plain=1#recovery)')

    def test_path_escape_and_blob_directory_are_rejected(self):
        for target in ('../../../outside.md', f'{self.base}/blob/v2.2.1/docs'):
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.render(f'[Invalid]({target})')

    def test_historical_refs_are_skipped_only_by_general_docs_checker(self):
        target = f'{self.base}/blob/v2.2.0/docs/historical.md'
        self.assertIsNone(local_target(target, self.document, self.root, '2.2.1'))

    def test_invalid_version_is_rejected_before_reading_a_path(self):
        with self.assertRaisesRegex(ValueError, 'Version must be'):
            notes.render(self.root, '../outside')

    def test_empty_curated_notes_cannot_replace_a_release_body(self):
        with self.assertRaisesRegex(ValueError, 'Empty curated release notes'):
            self.render(' \n\n')

    def test_invalid_links_leave_previous_output_untouched(self):
        self.document.write_text('[Broken](../missing.md)', encoding='utf-8')
        output = self.root / 'rendered.md'
        output.write_text('previous reviewed output', encoding='utf-8')
        result = sp.run([sys.executable, '-B', str(SCRIPT), '--root', str(self.root),
                         '--version', '2.2.1', '--output', str(output)], text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing', result.stderr)
        self.assertEqual(output.read_text(encoding='utf-8'), 'previous reviewed output')


if __name__ == '__main__':
    unittest.main()

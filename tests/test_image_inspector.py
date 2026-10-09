"""Registry failures may retry; component inspection must still fail closed."""
import importlib.util
from pathlib import Path
import subprocess as sp
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('image_checker', ROOT / 'scripts/testing/check-image.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
PIN = checker.pins.inspect_pins(ROOT)['go_builder']


class InspectorTests(unittest.TestCase):
    def test_exact_local_native_pin_needs_no_registry(self):
        with patch.object(checker.sp, 'run', return_value=Mock(returncode=0, stdout='linux/amd64\n')) as run:
            checker.ensure_inspector('docker', PIN, 'linux/amd64')
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][-1], PIN)

    def test_wrong_local_architecture_fetches_native_pin(self):
        with patch.object(checker.sp, 'run', side_effect=[Mock(returncode=0, stdout='linux/arm64\n'), Mock()]) as run:
            checker.ensure_inspector('docker', PIN, 'linux/amd64')
        self.assertEqual(run.call_args.args[0], ['docker', 'pull', '--platform', 'linux/amd64', PIN])

    def test_registry_failure_then_success_retries_same_pin(self):
        failure = sp.CalledProcessError(125, ['docker', 'pull'])
        with patch.object(checker.sp, 'run', side_effect=[Mock(returncode=1), failure, Mock()]) as run, \
                patch.object(checker.time, 'sleep') as sleep:
            checker.ensure_inspector('docker', PIN, 'linux/amd64')
        self.assertEqual(run.call_args_list[1].args[0], run.call_args_list[2].args[0])
        sleep.assert_called_once_with(10)

    def test_fetch_failure_exhausts_budget_and_blocks_inspection(self):
        failure = sp.CalledProcessError(125, ['docker', 'pull'])
        with patch.object(checker, 'run', return_value=b'amd64\n') as inspect, \
                patch.object(checker.sp, 'run', side_effect=[Mock(returncode=1), failure, failure, failure]) as fetch, \
                patch.object(checker.time, 'sleep') as sleep:
            with self.assertRaises(sp.CalledProcessError):
                checker.inspect_transport('docker', b'synthetic transport')
        self.assertEqual(fetch.call_count, 4)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [10, 20])
        self.assertEqual(inspect.call_count, 1)  # Host discovery only; no container inspection.

    def test_fetch_timeout_is_bounded(self):
        failure = sp.TimeoutExpired(['docker', 'pull'], 120)
        with patch.object(checker.sp, 'run', side_effect=[Mock(returncode=1), failure, failure, failure]) as run, \
                patch.object(checker.time, 'sleep'):
            with self.assertRaises(sp.TimeoutExpired):
                checker.ensure_inspector('docker', PIN, 'linux/amd64')
        self.assertTrue(all(call.kwargs['timeout'] == 120 for call in run.call_args_list[1:]))

    def test_inspection_is_offline_and_cannot_implicitly_pull(self):
        with patch.object(checker, 'ensure_inspector') as ensure, \
                patch.object(checker, 'run', side_effect=[b'arm64\n', b'build metadata']) as run:
            self.assertEqual(checker.inspect_transport('docker', b'synthetic transport'), 'build metadata')
        ensure.assert_called_once_with('docker', PIN, 'linux/arm64')
        command = run.call_args.args
        self.assertIn(PIN, command)
        self.assertIn('--pull=never', command)
        self.assertEqual(command[command.index('--network') + 1], 'none')
        self.assertEqual(command[command.index('--platform') + 1], 'linux/arm64')
        self.assertEqual(run.call_args.kwargs['input'], b'synthetic transport')

    def test_inspection_failure_is_not_retried(self):
        with patch.object(checker, 'ensure_inspector') as ensure, \
                patch.object(checker, 'run', side_effect=[b'amd64\n', sp.CalledProcessError(1, ['docker', 'run'])]) as run:
            with self.assertRaises(sp.CalledProcessError):
                checker.inspect_transport('docker', b'bad transport')
        self.assertEqual(ensure.call_count, 1)
        self.assertEqual(run.call_count, 2)

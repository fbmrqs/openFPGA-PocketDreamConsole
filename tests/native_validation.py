"""Exercise package isolation and non-cancelling diagnostic result collection."""
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import package_native
from rom_library import NATIVE_ROMS
spec=importlib.util.spec_from_file_location('diagnostic',ROOT/'tools/fpga/run-diagnostic.py')
diagnostic=importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class LibrarySelection(unittest.TestCase):
    def setUp(self):
        self.rom=NATIVE_ROMS[0]
        self.record={'completed':True,'passed':False,'frames_per_rom':1800,
            'system_inputs':{'source':'current'},'script_sha256':'script',
            'roms':{self.rom.key:{'sha256':'asset','videojet':self.rom.videojet}},
            'failures':{r.key:{'error':'playback budget exceeded'}for r in NATIVE_ROMS[1:]}}
        for name,value in (('inputs',{'source':'current'}),('digest','script'),
                           ('validate_native','asset'),('require',{'passed':True})):
            p=patch.object(package_native,name,return_value=value);p.start();self.addCleanup(p.stop)

    def test_failed_optional_roms_do_not_block_verified_rom(self):
        selected,receipts=package_native.verified_library(self.record)
        self.assertEqual([r.key for r in selected],[self.rom.key])
        self.assertEqual(list(receipts),['system-'+self.rom.key+'-pocket'])
        package_native.require.assert_called_once_with('system-'+self.rom.key+'-pocket')

    def test_stale_incomplete_and_conflicting_results_are_rejected(self):
        for change in ({'completed':False},{'system_inputs':{}},{'script_sha256':'old'},
                       {'failures':{**self.record['failures'],self.rom.key:{'error':'bad'}}}):
            with self.subTest(change=change),self.assertRaises(ValueError):
                package_native.verified_library({**self.record,**change})

    def test_missing_results_and_corrupt_asset_are_rejected(self):
        with self.assertRaises(ValueError):
            package_native.verified_library({**self.record,'failures':{}})
        package_native.validate_native.return_value='different'
        with self.assertRaises(ValueError):package_native.verified_library(self.record)

    def test_per_rom_receipt_remains_required(self):
        package_native.require.side_effect=ValueError('receipt is stale')
        with self.assertRaises(ValueError):package_native.verified_library(self.record)


class ResultCollection(unittest.TestCase):
    def test_failure_is_logged_without_cancelling_other_job(self):
        failed=Mock(pid=10);failed.poll.return_value=1
        running=Mock(pid=11);running.poll.side_effect=[None,0]
        jobs={name:{'process':process,'output':io.StringIO(),'component':None,'state':'running'}
              for name,process in (('pocket-pink',failed),('rom-library',running))}
        with tempfile.TemporaryDirectory()as directory,patch.object(diagnostic,'root',Path(directory)),patch.object(diagnostic,'jobs',jobs):
            diagnostic.monitor()
            self.assertEqual(jobs['pocket-pink']['state'],'failed')
            self.assertEqual(jobs['rom-library']['state'],'running')
            running.terminate.assert_not_called();running.kill.assert_not_called()
            diagnostic.monitor()
            result=json.loads((Path(directory)/'validation-jobs.json').read_text())['jobs']
            self.assertEqual(result['rom-library']['state'],'passed')
            self.assertEqual(list(diagnostic.failures(jobs)),['pocket-pink'])


if __name__=='__main__':unittest.main()

#!/usr/bin/env python3
"""The remote peer accepts bounded markers and retires only its owned process."""

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import verify_internet_coop_ssh as driver
spec = importlib.util.spec_from_file_location("remote_peer", ROOT / "tools/internet_coop_ssh_peer.py")
peer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(peer)
cleanup_spec=importlib.util.spec_from_file_location("remote_cleanup",ROOT/"tools/internet_coop_ssh_cleanup.py")
cleanup=importlib.util.module_from_spec(cleanup_spec)
cleanup_spec.loader.exec_module(cleanup)


def isolated_candidate(directory,case,slot):
    package=directory/"package"
    package.mkdir()
    binary=package/"Bunkercrew.x86_64"
    binary.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(60)\n")
    binary.chmod(0o700)
    library=package/"fixture.so"
    library.write_bytes(b"isolated library boundary fixture")
    return {"slot":slot,"case":case,"relay":"wss://bunkercrew.vibechain.rocks/ws",
            "binary_sha256":peer.digest(binary),"libraries":{"fixture.so":peer.digest(library)}}


class RemotePeerBoundaryTest(unittest.TestCase):
    def test_only_known_marker_paths_are_accepted(self):
        self.assertEqual(peer.stage_path(Path("/fixture"), "run.joined4.json"), Path("/fixture/run.joined4.json"))
        for name in ("../outside.json", "run/../../outside.json", "/tmp/outside", "other.room.json"):
            with self.assertRaises(ValueError): peer.stage_path(Path("/fixture"), name)

    def test_marker_payloads_are_bounded_and_ready(self):
        self.assertEqual(peer.stage_data('{"ready":true,"code":"fixture"}'), '{"ready":true,"code":"fixture"}')
        for data in ('[]', '{"ready":false}', '{"arbitrary":true}', "x"*(peer.MAX_STAGE+1)):
            with self.assertRaises(ValueError): peer.stage_data(data)

    def test_remote_directory_must_be_owned_private_and_temporary(self):
        with tempfile.TemporaryDirectory(prefix="bunkercrew-wan-", dir="/tmp") as temporary:
            path = Path(temporary)
            self.assertEqual(peer.private_directory(path), path)
            path.chmod(0o755)
            with self.assertRaises(ValueError): peer.private_directory(path)

    def test_coalesced_configuration_does_not_lose_following_stages(self):
        read, write = os.pipe()
        try:
            following = b'{"op":"stage","name":"run.room.json","data":"fixture"}\n'
            os.write(write, b'{"slot":4,"case":"leave"}\n'+following)
            with patch.object(peer.sys, "stdin", SimpleNamespace(fileno=lambda:read)):
                configuration, remaining = peer.read_configuration()
            self.assertEqual(configuration, {"slot":4,"case":"leave"})
            self.assertEqual(remaining, following)
        finally:
            os.close(read)
            os.close(write)

    def test_configuration_eof_is_a_failure(self):
        read, write = os.pipe()
        os.close(write)
        try:
            with patch.object(peer.sys, "stdin", SimpleNamespace(fileno=lambda:read)), self.assertRaises(ConnectionError):
                peer.read_configuration()
        finally:
            os.close(read)

    def test_bad_remote_hash_cannot_spawn_a_game(self):
        with tempfile.TemporaryDirectory(prefix="bunkercrew-wan-",dir="/tmp") as temporary:
            path=Path(temporary)
            (path/"package").mkdir()
            (path/"package/Bunkercrew.x86_64").write_bytes(b"fixture executable")
            configuration={"slot":4,"case":"leave","relay":"wss://bunkercrew.vibechain.rocks/ws","binary_sha256":"0"*64}
            with patch.object(peer.subprocess,"Popen") as spawn, self.assertRaises(ValueError):
                peer.start_game(path,configuration)
            spawn.assert_not_called()

    def test_timeout_cleanup_signals_only_the_owned_process_group(self):
        process=SimpleNamespace(pid=12345,poll=lambda:None)
        calls=iter((subprocess.TimeoutExpired("fixture",3),None))
        def wait(timeout):
            result=next(calls)
            if result is not None: raise result
        process.wait=wait
        with patch.object(peer.os,"killpg") as kill:
            peer.stop_owned(process)
        self.assertEqual(kill.call_args_list[0].args,(12345,signal.SIGTERM))
        self.assertEqual(kill.call_args_list[1].args,(12345,signal.SIGKILL))

    def test_broken_pid_publication_retires_the_actual_spawned_group(self):
        with tempfile.TemporaryDirectory(prefix="bunkercrew-wan-",dir="/tmp") as temporary:
            directory=Path(temporary)
            package=directory/"package"
            package.mkdir()
            binary=package/"Bunkercrew.x86_64"
            binary.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(60)\n")
            binary.chmod(0o700)
            library=package/"fixture.so"
            library.write_bytes(b"isolated native library hash fixture")
            configuration={"slot":4,"case":"leave","relay":"wss://bunkercrew.vibechain.rocks/ws",
                           "binary_sha256":peer.digest(binary),"libraries":{"fixture.so":peer.digest(library)}}
            children=[]
            original_spawn=subprocess.Popen
            def spawn(*args,**kwargs):
                child=original_spawn(*args,**kwargs)
                children.append(child)
                return child
            try:
                with patch.object(peer.subprocess,"Popen",side_effect=spawn), patch.object(peer,"publish",side_effect=BrokenPipeError("closed SSH stream")), self.assertRaises(BrokenPipeError):
                    peer.start_game(directory,configuration)
                self.assertEqual(len(children),1)
                self.assertIsNotNone(children[0].poll())
                with self.assertRaises(ProcessLookupError): os.killpg(children[0].pid,0)
            finally:
                for child in children: peer.stop_owned(child)

    def test_reused_foreign_pid_cannot_be_reported_as_owned_or_retired(self):
        configuration={"pid":os.getpid(),"directory":"/tmp/bunkercrew-wan-fixture","cwd":"/tmp/bunkercrew-wan-fixture/cwd","command":["/fixture/game"],"start_ticks":"0"}
        result=cleanup.observations(configuration)
        self.assertTrue(result["foreign_identity_detected"])
        self.assertFalse(result["retired"])

    def test_missing_owned_pid_and_group_certifies_retirement(self):
        result=cleanup.observations({"pid":2147483647,"directory":"/tmp/bunkercrew-wan-fixture"})
        self.assertTrue(result["retired"])
        self.assertEqual(result["group_members"],[])

    def test_failed_bridge_initialization_retires_its_actual_ssh_group(self):
        children=[]
        original_spawn=subprocess.Popen
        def spawn(_command,**kwargs):
            child=original_spawn([sys.executable,"-c","import time; time.sleep(60)"],**kwargs)
            actual_wait=child.wait
            first=True
            def wait(timeout):
                nonlocal first
                if first:
                    first=False
                    raise subprocess.TimeoutExpired("owned SSH fixture",timeout)
                return actual_wait(timeout=timeout)
            child.wait=wait
            children.append(child)
            return child
        args=SimpleNamespace(ssh="uncontacted-fixture",remote_slot=1,relay="wss://bunkercrew.vibechain.rocks/ws")
        selector=SimpleNamespace(register=lambda *_args: (_ for _ in ()).throw(OSError("selector initialization failed")),close=lambda:None)
        try:
            with tempfile.TemporaryDirectory(prefix="bunkercrew-bridge-boundary-") as temporary, patch.object(driver.subprocess,"Popen",side_effect=spawn), patch.object(driver.selectors,"DefaultSelector",return_value=selector), self.assertRaises(OSError):
                driver.Bridge(args,"/tmp/bunkercrew-wan-fixture","leave",Path(temporary)/"run",Path(temporary),{"sha256":"0"*64,"native_libraries":{}})
            self.assertEqual(len(children),1)
            self.assertIsNotNone(children[0].poll())
            with self.assertRaises(ProcessLookupError): os.killpg(children[0].pid,0)
        finally:
            for child in children: peer.stop_owned(child)

    def test_bridge_stop_escalates_only_its_group_after_both_deadlines(self):
        bridge=driver.Bridge.__new__(driver.Bridge)
        waits=iter((subprocess.TimeoutExpired("fixture",8),subprocess.TimeoutExpired("fixture",5),None))
        def wait(timeout):
            result=next(waits)
            if result is not None: raise result
        bridge.process=SimpleNamespace(pid=23456,poll=lambda:None,stdin=SimpleNamespace(closed=True),wait=wait)
        bridge.selector=SimpleNamespace(close=lambda:None)
        bridge.send=lambda _message:None
        with patch.object(driver.os,"killpg") as kill: bridge.stop()
        self.assertEqual([call.args for call in kill.call_args_list],[(23456,signal.SIGTERM),(23456,signal.SIGKILL)])

    def test_invalid_local_package_allocates_no_server_resource(self):
        args=SimpleNamespace(linux=Path("/missing-local-candidate"),ssh="uncontacted-fixture")
        with patch.object(driver.internet,"package_identity",side_effect=RuntimeError("invalid package")), patch.object(driver,"run_ssh") as ssh, self.assertRaises(RuntimeError):
            driver.prepare_remote(args,Path("/unused-output"))
        ssh.assert_not_called()

    def test_tire_dispatch_uses_embedded_fixture_and_rejects_other_classes(self):
        with tempfile.TemporaryDirectory(prefix="bunkercrew-wan-",dir="/tmp") as temporary:
            directory=Path(temporary)
            configuration=isolated_candidate(directory,"tire",4)
            process=None
            try:
                with patch.object(peer,"publish"):
                    process,folder,_log=peer.start_game(directory,configuration)
                self.assertIn('run/main_loop_type="BetaInternetCoopCheck"',(folder/"cwd/override.cfg").read_text())
                self.assertIsNone(process.poll())
                for case in ("../tire","tire/other","arbitraryClass"):
                    with patch.object(peer.subprocess,"Popen") as spawn, self.assertRaises(ValueError):
                        peer.start_game(directory,{**configuration,"case":case})
                    spawn.assert_not_called()
            finally: peer.stop_owned(process)

    def test_crash_requires_real_readiness_and_kills_only_actual_owned_group(self):
        with tempfile.TemporaryDirectory(prefix="bunkercrew-wan-",dir="/tmp") as temporary:
            directory=Path(temporary)
            configuration=isolated_candidate(directory,"crash",1)
            process=None
            try:
                with patch.object(peer,"publish"):
                    process,folder,_log=peer.start_game(directory,configuration)
                for invalid in ({**configuration,"slot":4},{**configuration,"case":"leave"},configuration):
                    with self.assertRaises(ValueError): peer.crash_owned_host(process,invalid,folder)
                    self.assertIsNone(process.poll())
                (folder/"run.host_departure_ready.json").write_text('{"ready":true,"mode":"crash"}')
                with patch.object(peer,"publish") as published:
                    peer.crash_owned_host(process,configuration,folder)
                self.assertEqual(process.returncode,-signal.SIGKILL)
                self.assertEqual(published.call_args.args[0],{"op":"crashed","pid":process.pid,"signal":int(signal.SIGKILL),"returncode":-signal.SIGKILL})
                with self.assertRaises(ProcessLookupError): os.killpg(process.pid,0)
            finally: peer.stop_owned(process)


if __name__=="__main__": unittest.main()

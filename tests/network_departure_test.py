"""Two real ENet processes; intentional host departure must end immediately."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/network-followup/departure"


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bunkercrew-departure-") as temporary:
        processes = []
        try:
            for role in ("host", "guest"):
                with (OUTPUT / f"{role}.log").open("w") as log:
                    processes.append(subprocess.Popen(
                        [shutil.which("godot"), "--headless", "--path", str(ROOT),
                         "--script", "tests/network_departure_peer.gd", "--",
                         "--no-profile-save", "--no-upnp"], cwd=ROOT,
                        env={**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role,
                             "LASTSHIFT_GAMEPLAY_PATH": str(Path(temporary) / "stage"),
                             "LASTSHIFT_TEST_PORT": "24931",
                             "LASTSHIFT_TEST_DISCOVERY_PORT": "24932"},
                        stdout=log, stderr=subprocess.STDOUT))
            for process in processes:
                assert process.wait(timeout=25) == 0
            for role in ("host", "guest"):
                text = (OUTPUT / f"{role}.log").read_text()
                assert "NETWORK_GAMEPLAY_PASS" in text, text
                assert not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")), text
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
    print("DIRECT DEPARTURE: intentional host leave passed in two real processes.")


if __name__ == "__main__":
    main()

import os
import pty
import select
import signal
import subprocess
import time


def drain_pty(fd, duration_s, label):
    end = time.time() + duration_s
    chunks = []
    while time.time() < end:
        rlist, _, _ = select.select([fd], [], [], 0.25)
        if not rlist:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError as e:
            chunks.append(f"\n[{label} read error] {e}\n".encode())
            break
        if not data:
            break
        chunks.append(data)
    if chunks:
        decoded = b"".join(chunks).decode("utf-8", errors="ignore")
        print(f"[{label} output]\n{decoded}\n[/{label} output]")
    else:
        print(f"[{label} output]\n<no output captured>\n[/{label} output]")


print("Starting autonomous test...")
backend = subprocess.Popen(
    ["python3", "-u", "backends/xai_beta_v2.py"],
    stderr=subprocess.PIPE,
    stdout=subprocess.PIPE,
)
time.sleep(2)

pid, fd = pty.fork()
if pid == 0:
    os.execl("./quantum_portal", "quantum_portal")
else:
    print(f"Portal child pid: {pid}")
    time.sleep(1)
    drain_pty(fd, 2, "portal-pre-input")

    print("Sending input: hello")
    os.write(fd, b"hello\r\n")
    drain_pty(fd, 12, "portal-post-input")

    child_pid, child_status = os.waitpid(pid, os.WNOHANG)
    if child_pid == 0:
        print("Portal child status: still running")
    else:
        if os.WIFEXITED(child_status):
            print(f"Portal child exited with code: {os.WEXITSTATUS(child_status)}")
        elif os.WIFSIGNALED(child_status):
            print(f"Portal child died from signal: {os.WTERMSIG(child_status)}")
        else:
            print(f"Portal child status raw: {child_status}")

    print("Backend exit code before terminate:", backend.poll())

    if child_pid == 0:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    backend.terminate()
    outs, errs = backend.communicate()
    print("Backend stderr:")
    print(errs.decode("utf-8", errors="ignore"))
    print("Backend stdout:")
    print(outs.decode("utf-8", errors="ignore"))
    print("Test complete.")

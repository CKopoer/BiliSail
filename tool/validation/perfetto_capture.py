"""Wait for Perfetto to close its output before copying a completed trace."""
import time


def stop_and_wait(adb, trace_pid, timeout=15):
    adb('shell', f'kill -INT {trace_pid}', check=False)
    deadline = time.monotonic() + timeout
    while True:
        status = adb('shell', 'cat', f'/proc/{trace_pid}/stat', check=False)
        # A zombie has closed its file descriptors but may await shell reaping.
        if not status or status.partition(')')[2].lstrip().startswith('Z '):
            return
        if time.monotonic() >= deadline:
            raise TimeoutError('Perfetto did not finish writing the trace')
        time.sleep(.1)

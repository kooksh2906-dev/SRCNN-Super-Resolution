import io
import json
import threading
import time
import unittest
import urllib.request
from http.server import ThreadingHTTPServer

import numpy as np
from PIL import Image

from srcnn_backend import TileResult
from srcnn_web_ui import BackendSettings, INDEX_HTML, JobManager, make_handler


class ZeroBackend:
    name = 'zero-test'

    def run_tile(self, tile_id, input_tile):
        return TileResult(
            tile_id=tile_id,
            output=np.zeros((1, 16, 16), dtype=np.int16),
            cycle_count=1,
            elapsed_seconds=0.0,
            backend_name=self.name,
        )

    def close(self):
        pass


class ConcurrencyProbeBackend(ZeroBackend):
    lock = threading.Lock()
    active = 0
    max_active = 0

    def __init__(self):
        with self.lock:
            type(self).active += 1
            type(self).max_active = max(type(self).max_active, type(self).active)

    def run_tile(self, tile_id, input_tile):
        if tile_id == 0:
            time.sleep(0.05)
        return super().run_tile(tile_id, input_tile)

    def close(self):
        with self.lock:
            type(self).active -= 1


class SrcnnWebUiTest(unittest.TestCase):
    def setUp(self):
        manager = JobManager(backend_factory=lambda settings: ZeroBackend())
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(manager))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        host, port = self.server.server_address
        self.base_url = f'http://{host}:{port}'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2.0)

    def test_index_contains_controls(self):
        with urllib.request.urlopen(self.base_url, timeout=2.0) as response:
            body = response.read().decode('utf-8')
        self.assertIn('SRCNN INT16 Super-Resolution', body)
        self.assertIn('사진 선택', body)
        self.assertIn('시연 모드', body)
        self.assertIn('평가 모드', body)
        self.assertIn('동일 영역 4× 확대 비교', body)
        self.assertIn('ZYBO UART', body)
        self.assertIn('Serial Port', body)
        self.assertIn('/api/jobs', INDEX_HTML)

    def test_config_defaults_to_python(self):
        with urllib.request.urlopen(self.base_url + '/api/config', timeout=2.0) as response:
            config = json.load(response)
        self.assertEqual(config['backend'], 'python')
        self.assertEqual(config['baudrate'], 115200)
        self.assertIsInstance(config['serial_ports'], list)

    def test_backend_settings_validate_zybo_port(self):
        with self.assertRaises(ValueError):
            BackendSettings(kind='zybo')
        settings = BackendSettings.from_headers(
            {
                'X-Backend': 'zybo',
                'X-Serial-Port': '/dev/ttyUSB0',
                'X-Baud': '230400',
                'X-Uart-Timeout': '7.5',
                'X-Retries': '2',
            },
            BackendSettings(),
        )
        self.assertEqual(settings.kind, 'zybo')
        self.assertEqual(settings.serial_port, '/dev/ttyUSB0')
        self.assertEqual(settings.baudrate, 230400)
        self.assertEqual(settings.timeout, 7.5)
        self.assertEqual(settings.retries, 2)

    def test_zybo_jobs_are_serialized(self):
        ConcurrencyProbeBackend.active = 0
        ConcurrencyProbeBackend.max_active = 0
        manager = JobManager(
            backend_factory=lambda settings: ConcurrencyProbeBackend()
        )
        buffer = io.BytesIO()
        Image.new('RGB', (128, 128), (20, 40, 60)).save(buffer, format='PNG')
        settings = BackendSettings(kind='zybo', serial_port='mock-port')
        jobs = [
            manager.create(f'test-{index}.png', buffer.getvalue(), settings)
            for index in range(2)
        ]
        deadline = time.monotonic() + 3.0
        while any(job.status not in ('done', 'error', 'cancelled') for job in jobs):
            if time.monotonic() >= deadline:
                self.fail('serialized ZYBO jobs did not finish')
            time.sleep(0.01)
        self.assertEqual([job.status for job in jobs], ['done', 'done'])
        self.assertEqual(ConcurrencyProbeBackend.max_active, 1)

    def test_hr_upload_job_returns_comparison_images(self):
        buffer = io.BytesIO()
        Image.new('RGB', (256, 256), (50, 100, 150)).save(buffer, format='PNG')
        request = urllib.request.Request(
            self.base_url + '/api/jobs',
            data=buffer.getvalue(),
            method='POST',
            headers={'Content-Type': 'image/png', 'X-Filename': 'test.png'},
        )
        with urllib.request.urlopen(request, timeout=2.0) as response:
            job_id = json.load(response)['job_id']

        deadline = time.monotonic() + 3.0
        while True:
            with urllib.request.urlopen(
                self.base_url + f'/api/jobs/{job_id}', timeout=2.0
            ) as response:
                job = json.load(response)
            if job['status'] in ('done', 'error', 'cancelled'):
                break
            if time.monotonic() >= deadline:
                self.fail('web UI job did not finish')
            time.sleep(0.01)

        self.assertEqual(job['status'], 'done', job.get('error'))
        self.assertEqual(job['progress'], 256)
        self.assertEqual(
            set(job['result']) >= {
                'source', 'hr', 'has_hr', 'lr', 'bicubic', 'sr',
                'demo_metrics', 'evaluation_metrics',
            },
            True,
        )
        self.assertTrue(job['result']['has_hr'])
        self.assertEqual(job['result']['backend_name'], 'zero-test')
        self.assertIn('zero-test 처리시간', job['message'])
        self.assertTrue(job['result']['hr'].startswith('data:image/png;base64,'))
        self.assertTrue(job['result']['sr'].startswith('data:image/png;base64,'))


if __name__ == '__main__':
    unittest.main()

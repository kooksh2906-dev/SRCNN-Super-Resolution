"""추가 GUI 패키지 없이 실행하는 SRCNN 임시 Web UI."""

from __future__ import annotations

import argparse
import base64
import io
import json
import threading
import uuid
import webbrowser
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable
from urllib.parse import urlparse

from PIL import Image

from srcnn_backend import PythonInt16Backend, SrcnnBackend, ZyboUartBackend
from srcnn_demo_image import calculate_y_psnr, prepare_demo_image, reconstruct_sr_rgb
from srcnn_pipeline import PipelineCancelled, run_pipeline
from uart_host import list_serial_ports


ROOT = Path(__file__).resolve().parent
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


@dataclass(frozen=True)
class BackendSettings:
    """UI 작업 하나에 적용할 Python/ZYBO Backend 설정."""

    kind: str = 'python'
    serial_port: str | None = None
    baudrate: int = 115200
    timeout: float = 10.0
    retries: int = 0

    def __post_init__(self) -> None:
        normalized = self.kind.strip().lower()
        object.__setattr__(self, 'kind', normalized)
        if normalized not in ('python', 'zybo'):
            raise ValueError(f'지원하지 않는 Backend입니다: {self.kind}')
        if self.baudrate <= 0:
            raise ValueError('Baud rate는 양수여야 합니다.')
        if self.timeout <= 0:
            raise ValueError('UART timeout은 양수여야 합니다.')
        if self.retries < 0:
            raise ValueError('재시도 횟수는 0 이상이어야 합니다.')
        if normalized == 'zybo' and not self.serial_port:
            raise ValueError('ZYBO UART Backend에는 Serial Port가 필요합니다.')

    @classmethod
    def from_headers(cls, headers, default: 'BackendSettings') -> 'BackendSettings':
        kind = headers.get('X-Backend', default.kind).strip().lower()
        port = headers.get('X-Serial-Port', default.serial_port or '').strip() or None
        try:
            baudrate = int(headers.get('X-Baud', str(default.baudrate)))
            timeout = float(headers.get('X-Uart-Timeout', str(default.timeout)))
            retries = int(headers.get('X-Retries', str(default.retries)))
        except ValueError as error:
            raise ValueError('UART 설정값의 숫자 형식이 올바르지 않습니다.') from error
        return cls(kind, port, baudrate, timeout, retries)

    def snapshot(self) -> dict:
        return {
            'backend': self.kind,
            'serial_port': self.serial_port,
            'baudrate': self.baudrate,
            'timeout': self.timeout,
            'retries': self.retries,
        }


def create_backend(settings: BackendSettings) -> SrcnnBackend:
    if settings.kind == 'python':
        return PythonInt16Backend(
            parameter_dir=ROOT / 'dump_int16',
            valid_masks=ROOT / 'full_image_data' / 'tile_valid_masks.npy',
        )
    return ZyboUartBackend(
        port=settings.serial_port,
        baudrate=settings.baudrate,
        timeout=settings.timeout,
        retries=settings.retries,
    )


INDEX_HTML = r"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SRCNN INT16 FPGA Demo</title>
  <style>
    :root { color-scheme: dark; --bg:#0b1020; --panel:#151c30; --line:#28334f;
      --text:#edf2ff; --muted:#9cabc9; --accent:#6c8cff; --good:#4fd1a5; }
    * { box-sizing:border-box; }
    body { margin:0; background:linear-gradient(135deg,#090d19,#111a31); color:var(--text);
      font-family:"Malgun Gothic",system-ui,sans-serif; min-height:100vh; }
    main { max-width:1220px; margin:auto; padding:34px 28px; }
    h1 { margin:0 0 6px; font-size:28px; }
    .subtitle,.meta { color:var(--muted); }
    .toolbar { display:flex; align-items:center; gap:10px; margin:24px 0 18px; flex-wrap:wrap; }
    button,.file-button,.save-button { border:1px solid var(--line); background:#202a45; color:var(--text);
      border-radius:9px; padding:10px 16px; font-weight:700; cursor:pointer; text-decoration:none; }
    button.primary { background:var(--accent); border-color:var(--accent); color:white; }
    button:disabled,.save-button.disabled { opacity:.42; cursor:not-allowed; pointer-events:none; }
    input[type=file] { display:none; }
    .backend { margin-left:auto; color:var(--muted); }
    .backend-config { display:flex; align-items:end; gap:10px; margin:0 0 16px; padding:13px;
      flex-wrap:wrap; background:rgba(21,28,48,.92); border:1px solid var(--line); border-radius:12px; }
    .backend-config label { display:grid; gap:5px; color:var(--muted); font-size:12px; }
    .backend-config select,.backend-config input { min-width:120px; border:1px solid var(--line);
      border-radius:8px; padding:9px 10px; background:#0f1628; color:var(--text); }
    .serial-config { display:flex; align-items:end; gap:10px; flex-wrap:wrap; }
    #serialPort { min-width:180px; }
    .modebar { display:flex; align-items:center; gap:8px; margin:0 0 16px; }
    .modebar button { padding:8px 14px; }
    .modebar button.active { background:#334476; border-color:#7892ef; }
    .mode-hint { color:var(--muted); margin-left:7px; font-size:13px; }
    .grid { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:14px; }
    .card { background:rgba(21,28,48,.92); border:1px solid var(--line); border-radius:14px;
      padding:13px; min-width:0; }
    .card h2 { font-size:14px; margin:0 0 11px; color:#c8d4ef; }
    .image-box { aspect-ratio:1; border-radius:9px; background:#0a0e1a; overflow:hidden;
      display:grid; place-items:center; color:#66728d; }
    .image-box img { width:100%; height:100%; object-fit:contain; image-rendering:auto; }
    .image-box img.pixelated { image-rendering:pixelated; }
    .zoom-section { margin-top:18px; }
    .zoom-header { display:flex; justify-content:space-between; align-items:end; gap:18px;
      margin:0 0 10px; flex-wrap:wrap; }
    .zoom-header h2 { margin:0; font-size:17px; }
    .zoom-controls { display:flex; gap:14px; color:var(--muted); font-size:13px; }
    .zoom-controls label { display:flex; align-items:center; gap:7px; }
    .zoom-grid { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:14px; }
    .zoom-box { aspect-ratio:1; border-radius:9px; background:#0a0e1a center/400% 400% no-repeat;
      border:1px solid #303c59; image-rendering:pixelated; }
    .hidden { display:none !important; }
    .progress-wrap { margin-top:20px; background:var(--panel); border:1px solid var(--line);
      border-radius:14px; padding:16px; }
    progress { width:100%; height:14px; accent-color:var(--accent); }
    #status { margin-top:10px; }
    #metrics { margin-top:6px; color:var(--good); font-weight:700; min-height:1.5em; }
    @media(max-width:900px) { .grid,.zoom-grid { grid-template-columns:1fr; }
      .backend { width:100%; margin:0; } }
  </style>
</head>
<body><main>
  <h1>SRCNN INT16 Super-Resolution</h1>
  <div class="subtitle">128×128 LR → Bicubic 256×256 → 256 Halo Tiles → Python 또는 ZYBO UART</div>
  <div class="toolbar">
    <label class="file-button" for="fileInput">사진 선택</label>
    <input id="fileInput" type="file" accept="image/png,image/jpeg,image/bmp">
    <button id="runButton" class="primary" disabled>SRCNN 실행</button>
    <button id="cancelButton" disabled>취소</button>
    <a id="saveButton" class="save-button disabled" download="srcnn_result_256.png">결과 저장</a>
    <span id="backendState" class="backend">Backend: Python INT16</span>
  </div>
  <section class="backend-config">
    <label>Backend
      <select id="backendSelect">
        <option value="python">Python INT16</option>
        <option value="zybo">ZYBO UART</option>
      </select>
    </label>
    <div id="serialSettings" class="serial-config hidden">
      <label>Serial Port
        <input id="serialPort" list="serialPortList" placeholder="COM5 또는 /dev/ttyUSB0">
        <datalist id="serialPortList"></datalist>
      </label>
      <button id="refreshPorts" type="button">포트 새로고침</button>
      <label>Baud
        <input id="baudRate" type="number" min="1" value="115200">
      </label>
      <label>Timeout (초)
        <input id="uartTimeout" type="number" min="0.1" step="0.1" value="10">
      </label>
      <label>Retry
        <input id="uartRetries" type="number" min="0" step="1" value="0">
      </label>
    </div>
  </section>
  <section class="modebar">
    <button id="demoMode" class="active">시연 모드</button>
    <button id="evaluationMode" disabled>평가 모드 · HR</button>
    <span id="modeHint" class="mode-hint">LR → Bicubic → SRCNN 변화에 집중합니다.</span>
  </section>
  <section class="grid">
    <article class="card"><h2 id="primaryTitle">LR 128×128 · 화면 확대</h2><div class="image-box"><img id="primary" hidden><span>이미지 없음</span></div></article>
    <article class="card"><h2>Bicubic 256×256</h2><div class="image-box"><img id="bicubic" hidden><span>실행 대기</span></div></article>
    <article class="card"><h2>SRCNN 256×256</h2><div class="image-box"><img id="sr" hidden><span>실행 대기</span></div></article>
  </section>
  <section id="zoomSection" class="zoom-section hidden">
    <div class="zoom-header">
      <div><h2>동일 영역 4× 확대 비교</h2><div id="roiLabel" class="meta">좌표 (96, 96), 64×64 영역</div></div>
      <div class="zoom-controls">
        <label>X <input id="roiX" type="range" min="0" max="192" value="96"></label>
        <label>Y <input id="roiY" type="range" min="0" max="192" value="96"></label>
      </div>
    </div>
    <div class="zoom-grid">
      <article id="zoomHrCard" class="card hidden"><h2>HR 정답 확대</h2><div id="zoomHr" class="zoom-box"></div></article>
      <article class="card"><h2>Bicubic 확대</h2><div id="zoomBicubic" class="zoom-box"></div></article>
      <article class="card"><h2>SRCNN 확대</h2><div id="zoomSr" class="zoom-box"></div></article>
    </div>
  </section>
  <section class="progress-wrap">
    <progress id="progress" value="0" max="256"></progress>
    <div id="status">128×128 LR 또는 256×256 HR 이미지를 선택하세요.</div>
    <div id="metrics"></div>
  </section>
</main>
<script>
  const $ = id => document.getElementById(id);
  let selectedFile = null, jobId = null, sourceUrl = null, lastResult = null;
  let currentMode = 'demo';
  const backendControls=['backendSelect','serialPort','refreshPorts','baudRate','uartTimeout','uartRetries'];
  function showImage(id, url) {
    const image = $(id), placeholder = image.nextElementSibling;
    image.src = url; image.hidden = false; placeholder.hidden = true;
  }
  function clearImage(id, text='실행 대기') {
    const image = $(id), placeholder = image.nextElementSibling;
    image.hidden = true; image.removeAttribute('src'); placeholder.textContent=text; placeholder.hidden=false;
  }
  function busy(value) {
    $('fileInput').disabled=value; $('runButton').disabled=value || !selectedFile;
    $('cancelButton').disabled=!value;
    backendControls.forEach(id => $(id).disabled=value);
  }
  function updateBackendControls() {
    const zybo=$('backendSelect').value==='zybo';
    $('serialSettings').classList.toggle('hidden',!zybo);
    $('backendState').textContent=zybo ? 'Backend: ZYBO UART' : 'Backend: Python INT16';
  }
  async function refreshPorts() {
    try {
      const response=await fetch('/api/config'), config=await response.json();
      if(!response.ok) throw new Error(config.error || '설정 조회 실패');
      const list=$('serialPortList'); list.innerHTML='';
      (config.serial_ports || []).forEach(port => {
        const option=document.createElement('option'); option.value=port.device;
        option.label=port.description || port.device; list.appendChild(option);
      });
      return config;
    } catch(error) {
      $('status').textContent=`Serial Port 조회 실패: ${error.message}`;
      return null;
    }
  }
  async function initializeBackendControls() {
    const config=await refreshPorts();
    if(config) {
      $('backendSelect').value=config.backend;
      $('serialPort').value=config.serial_port || '';
      $('baudRate').value=config.baudrate;
      $('uartTimeout').value=config.timeout;
      $('uartRetries').value=config.retries;
    }
    updateBackendControls();
  }
  function setMode(mode) {
    if (mode === 'evaluation' && (!lastResult || !lastResult.has_hr)) return;
    currentMode=mode;
    $('demoMode').classList.toggle('active',mode==='demo');
    $('evaluationMode').classList.toggle('active',mode==='evaluation');
    $('zoomHrCard').classList.toggle('hidden',mode!=='evaluation');
    if (!lastResult) return;
    if (mode === 'demo') {
      $('primaryTitle').textContent='LR 128×128 · 화면 확대';
      showImage('primary',lastResult.lr);
      $('primary').classList.add('pixelated');
      $('modeHint').textContent='LR → Bicubic → SRCNN 변화에 집중합니다.';
      $('metrics').textContent=lastResult.demo_metrics;
    } else {
      $('primaryTitle').textContent='HR 정답 256×256';
      showImage('primary',lastResult.hr);
      $('primary').classList.remove('pixelated');
      $('modeHint').textContent='HR 정답과 PSNR로 결과를 검증합니다.';
      $('metrics').textContent=lastResult.evaluation_metrics;
    }
    updateZoom();
  }
  function updateZoom() {
    if (!lastResult) return;
    const x=Number($('roiX').value), y=Number($('roiY').value);
    const position=`${x / 192 * 100}% ${y / 192 * 100}%`;
    $('roiLabel').textContent=`좌표 (${x}, ${y}), 64×64 영역`;
    $('zoomBicubic').style.backgroundImage=`url("${lastResult.bicubic}")`;
    $('zoomSr').style.backgroundImage=`url("${lastResult.sr}")`;
    $('zoomHr').style.backgroundImage=lastResult.hr ? `url("${lastResult.hr}")` : 'none';
    ['zoomBicubic','zoomSr','zoomHr'].forEach(id=>$(id).style.backgroundPosition=position);
  }
  $('demoMode').addEventListener('click',()=>setMode('demo'));
  $('evaluationMode').addEventListener('click',()=>setMode('evaluation'));
  $('backendSelect').addEventListener('change',updateBackendControls);
  $('refreshPorts').addEventListener('click',refreshPorts);
  $('roiX').addEventListener('input',updateZoom);
  $('roiY').addEventListener('input',updateZoom);
  $('fileInput').addEventListener('change', event => {
    selectedFile = event.target.files[0] || null;
    if (sourceUrl) URL.revokeObjectURL(sourceUrl);
    if (!selectedFile) return;
    lastResult=null; setMode('demo');
    $('primaryTitle').textContent='선택 이미지 · 실행 전';
    sourceUrl=URL.createObjectURL(selectedFile); showImage('primary',sourceUrl);
    $('primary').classList.remove('pixelated');
    ['bicubic','sr'].forEach(id=>clearImage(id));
    $('evaluationMode').disabled=true;
    $('zoomSection').classList.add('hidden');
    $('modeHint').textContent='실행 후 LR → Bicubic → SRCNN 비교로 전환됩니다.';
    $('saveButton').classList.add('disabled'); $('saveButton').removeAttribute('href');
    $('progress').value=0; $('metrics').textContent='';
    $('status').textContent=`${selectedFile.name} 선택됨 · 크기는 실행 시 확인합니다.`;
    $('runButton').disabled=false;
  });
  $('runButton').addEventListener('click', async () => {
    if (!selectedFile) return;
    if ($('backendSelect').value==='zybo' && !$('serialPort').value.trim()) {
      fail('ZYBO UART Backend를 사용하려면 Serial Port를 입력하세요.'); return;
    }
    busy(true); $('progress').value=0; $('metrics').textContent='';
    $('status').textContent='이미지 전처리 및 Backend 준비 중...';
    try {
      const headers={
        'Content-Type':selectedFile.type || 'application/octet-stream',
        'X-Filename':encodeURIComponent(selectedFile.name),
        'X-Backend':$('backendSelect').value,
        'X-Serial-Port':$('serialPort').value.trim(),
        'X-Baud':$('baudRate').value,
        'X-Uart-Timeout':$('uartTimeout').value,
        'X-Retries':$('uartRetries').value,
      };
      const response=await fetch('/api/jobs',{method:'POST',headers,body:selectedFile});
      const body=await response.json(); if(!response.ok) throw new Error(body.error || '작업 생성 실패');
      jobId=body.job_id; pollJob();
    } catch(error) { fail(error.message); }
  });
  $('cancelButton').addEventListener('click', async () => {
    if(jobId) await fetch(`/api/jobs/${jobId}/cancel`,{method:'POST'});
  });
  async function pollJob() {
    try {
      const response=await fetch(`/api/jobs/${jobId}`), job=await response.json();
      if(!response.ok) throw new Error(job.error || '상태 확인 실패');
      $('progress').value=job.progress;
      $('status').textContent=job.message;
      if(job.status==='done') {
        lastResult=job.result;
        showImage('bicubic',job.result.bicubic); showImage('sr',job.result.sr);
        $('evaluationMode').disabled=!job.result.has_hr;
        $('zoomSection').classList.remove('hidden');
        setMode('demo');
        $('saveButton').href=job.result.sr; $('saveButton').classList.remove('disabled');
        busy(false); jobId=null; return;
      }
      if(job.status==='error' || job.status==='cancelled') { fail(job.error || job.message); return; }
      setTimeout(pollJob,150);
    } catch(error) { fail(error.message); }
  }
  function fail(message) { busy(false); jobId=null; $('status').textContent=message; alert(message); }
  initializeBackendControls();
</script></body></html>"""


def image_data_url(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format='PNG')
    encoded = base64.b64encode(buffer.getvalue()).decode('ascii')
    return f'data:image/png;base64,{encoded}'


@dataclass
class Job:
    job_id: str
    filename: str
    backend_settings: BackendSettings = field(default_factory=BackendSettings)
    status: str = 'queued'
    progress: int = 0
    total: int = 256
    message: str = '작업 대기 중...'
    error: str | None = None
    result: dict | None = None
    cancel_event: threading.Event = field(default_factory=threading.Event)

    def snapshot(self) -> dict:
        return {
            'job_id': self.job_id,
            'status': self.status,
            'progress': self.progress,
            'total': self.total,
            'message': self.message,
            'error': self.error,
            'result': self.result,
            'backend_settings': self.backend_settings.snapshot(),
        }


class JobManager:
    def __init__(
        self,
        backend_factory: Callable[[BackendSettings], SrcnnBackend] | None = None,
        default_settings: BackendSettings | None = None,
    ):
        self.backend_factory = backend_factory or create_backend
        self.default_settings = default_settings or BackendSettings()
        self.jobs: dict[str, Job] = {}
        self.lock = threading.Lock()
        self.uart_lock = threading.Lock()

    def configuration(self) -> dict:
        config = self.default_settings.snapshot()
        try:
            ports = [
                {'device': device, 'description': description}
                for device, description in list_serial_ports()
            ]
            serial_error = None
        except (OSError, RuntimeError) as error:
            ports = []
            serial_error = str(error)
        config['serial_ports'] = ports
        config['serial_error'] = serial_error
        return config

    def create(
        self,
        filename: str,
        payload: bytes,
        backend_settings: BackendSettings | None = None,
    ) -> Job:
        if not payload:
            raise ValueError('빈 이미지 파일입니다.')
        if len(payload) > MAX_UPLOAD_BYTES:
            raise ValueError('이미지 파일은 10 MB 이하여야 합니다.')
        job = Job(
            job_id=uuid.uuid4().hex,
            filename=filename,
            backend_settings=backend_settings or self.default_settings,
        )
        with self.lock:
            self.jobs[job.job_id] = job
        threading.Thread(target=self._run, args=(job, payload), daemon=True).start()
        return job

    def get(self, job_id: str) -> Job | None:
        with self.lock:
            return self.jobs.get(job_id)

    def cancel(self, job_id: str) -> bool:
        job = self.get(job_id)
        if job is None:
            return False
        job.cancel_event.set()
        return True

    def _run(self, job: Job, payload: bytes) -> None:
        backend = None
        uart_acquired = False
        try:
            job.status = 'running'
            job.message = '이미지 전처리 중...'
            with Image.open(io.BytesIO(payload)) as source:
                demo = prepare_demo_image(source)

            if job.backend_settings.kind == 'zybo':
                job.message = 'ZYBO UART 사용 가능 상태를 기다리는 중...'
                while not self.uart_lock.acquire(timeout=0.1):
                    if job.cancel_event.is_set():
                        raise PipelineCancelled('cancelled while waiting for UART')
                uart_acquired = True

            backend = self.backend_factory(job.backend_settings)

            def progress(done, total, tile_result) -> None:
                job.progress = done
                job.total = total
                job.message = (
                    f'Tile {done}/{total} 처리 중 · '
                    f'{tile_result.backend_name} · '
                    f'최근 Tile {tile_result.elapsed_seconds * 1000:.1f} ms'
                )

            pipeline = run_pipeline(
                backend,
                demo.input_tiles_int16,
                progress_callback=progress,
                cancel_callback=job.cancel_event.is_set,
            )
            sr = reconstruct_sr_rgb(demo, pipeline.merged_output)
            if demo.reference_hr_rgb is not None:
                bicubic_psnr = calculate_y_psnr(
                    demo.reference_hr_rgb,
                    demo.bicubic_rgb,
                )
                sr_psnr = calculate_y_psnr(demo.reference_hr_rgb, sr)
                evaluation_metrics = (
                    f'Y-PSNR  Bicubic {bicubic_psnr:.2f} dB · '
                    f'SRCNN {sr_psnr:.2f} dB · 변화 {sr_psnr - bicubic_psnr:+.2f} dB'
                )
            else:
                evaluation_metrics = 'HR 기준 이미지가 없어 PSNR은 계산하지 않습니다.'

            demo_metrics = (
                f'{pipeline.backend_name} · LR 128×128 → SR 256×256 · '
                f'256 Tiles · 처리시간 {pipeline.elapsed_seconds:.3f}초'
            )
            if pipeline.total_cycle_count > 0:
                demo_metrics += f' · FPGA Cycle {pipeline.total_cycle_count:,}'

            has_hr = demo.reference_hr_rgb is not None

            job.result = {
                'source': image_data_url(demo.source_rgb),
                'hr': (
                    image_data_url(demo.reference_hr_rgb)
                    if demo.reference_hr_rgb is not None
                    else None
                ),
                'has_hr': has_hr,
                'lr': image_data_url(demo.lr_rgb),
                'bicubic': image_data_url(demo.bicubic_rgb),
                'sr': image_data_url(sr),
                'source_mode': demo.source_mode,
                'backend_name': pipeline.backend_name,
                'elapsed_seconds': pipeline.elapsed_seconds,
                'total_cycle_count': pipeline.total_cycle_count,
                'demo_metrics': demo_metrics,
                'evaluation_metrics': evaluation_metrics,
                'metrics': evaluation_metrics,
            }
            job.progress = 256
            job.status = 'done'
            job.message = (
                f'완료 · {demo.source_mode} · 256 Tiles · '
                f'{pipeline.backend_name} 처리시간 {pipeline.elapsed_seconds:.3f}초'
            )
        except PipelineCancelled:
            job.status = 'cancelled'
            job.message = '실행이 취소되었습니다.'
        except Exception as error:
            job.status = 'error'
            job.error = str(error)
            job.message = f'오류: {error}'
        finally:
            if backend is not None:
                backend.close()
            if uart_acquired:
                self.uart_lock.release()


def make_handler(manager: JobManager):
    class RequestHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            path = urlparse(self.path).path
            if path == '/':
                self._send_bytes(200, INDEX_HTML.encode('utf-8'), 'text/html; charset=utf-8')
                return
            if path == '/api/config':
                self._send_json(200, manager.configuration())
                return
            parts = path.strip('/').split('/')
            if len(parts) == 3 and parts[:2] == ['api', 'jobs']:
                job = manager.get(parts[2])
                if job is None:
                    self._send_json(404, {'error': '작업을 찾을 수 없습니다.'})
                else:
                    self._send_json(200, job.snapshot())
                return
            self._send_json(404, {'error': '경로를 찾을 수 없습니다.'})

        def do_POST(self) -> None:
            path = urlparse(self.path).path
            if path == '/api/jobs':
                try:
                    length = int(self.headers.get('Content-Length', '0'))
                    if length > MAX_UPLOAD_BYTES:
                        raise ValueError('이미지 파일은 10 MB 이하여야 합니다.')
                    payload = self.rfile.read(length)
                    filename = self.headers.get('X-Filename', 'input-image')
                    settings = BackendSettings.from_headers(
                        self.headers,
                        manager.default_settings,
                    )
                    job = manager.create(filename, payload, settings)
                    self._send_json(202, {'job_id': job.job_id})
                except (ValueError, OSError) as error:
                    self._send_json(400, {'error': str(error)})
                return
            parts = path.strip('/').split('/')
            if len(parts) == 4 and parts[:2] == ['api', 'jobs'] and parts[3] == 'cancel':
                if manager.cancel(parts[2]):
                    self._send_json(200, {'status': 'cancelling'})
                else:
                    self._send_json(404, {'error': '작업을 찾을 수 없습니다.'})
                return
            self._send_json(404, {'error': '경로를 찾을 수 없습니다.'})

        def _send_json(self, status: int, body: dict) -> None:
            payload = json.dumps(body, ensure_ascii=False).encode('utf-8')
            self._send_bytes(status, payload, 'application/json; charset=utf-8')

        def _send_bytes(self, status: int, payload: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(payload)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, format: str, *args) -> None:
            return

    return RequestHandler


def main() -> None:
    parser = argparse.ArgumentParser(description='Run the temporary SRCNN Web UI.')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--backend', choices=('python', 'zybo'), default='python')
    parser.add_argument('--serial-port', help='COM5 또는 /dev/ttyUSB0')
    parser.add_argument('--baud', type=int, default=115200)
    parser.add_argument('--uart-timeout', type=float, default=10.0)
    parser.add_argument('--retries', type=int, default=0)
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()

    if args.backend == 'zybo' and not args.serial_port:
        parser.error('--backend zybo에는 --serial-port가 필요합니다.')
    try:
        default_settings = BackendSettings(
            kind=args.backend,
            serial_port=args.serial_port,
            baudrate=args.baud,
            timeout=args.uart_timeout,
            retries=args.retries,
        )
    except ValueError as error:
        parser.error(str(error))

    manager = JobManager(default_settings=default_settings)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(manager))
    url = f'http://{args.host}:{args.port}'
    print(f'SRCNN UI: {url}')
    print(f'기본 Backend: {args.backend}')
    print('종료: Ctrl+C')
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n서버를 종료합니다.')
    finally:
        server.server_close()


if __name__ == '__main__':
    main()

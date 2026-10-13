/**
 * UPI OFFLINE MESH — 3:4 Deterministic Video Capture Engine
 * Captures 60fps high-bitrate video directly from the HTML5 canvas.
 * Supports Master (1440x1920) and Social/IG (1080x1440) export presets.
 */

class TeaserRecorder {
  constructor(canvas, animationEngine) {
    this.canvas = canvas;
    this.engine = animationEngine;
    this.mediaRecorder = null;
    this.recordedChunks = [];
    this.isRecording = false;
    this.banner = document.getElementById('recording-banner');
    this.statusText = document.getElementById('rec-status');
    this.presetSelect = document.getElementById('export-preset');
  }

  startRecording() {
    if (this.isRecording) return;
    
    if (!window.MediaRecorder) {
      alert('MediaRecorder API is not supported in this browser.');
      return;
    }

    const preset = this.presetSelect ? this.presetSelect.value : 'social';
    console.log(`Starting 3:4 recording with preset: ${preset}`);

    const stream = this.canvas.captureStream(60); // 60 FPS
    
    let options = { mimeType: 'video/webm;codecs=vp9', videoBitsPerSecond: 24000000 };
    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
      options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 18000000 };
      if (!MediaRecorder.isTypeSupported(options.mimeType)) {
        options = { mimeType: 'video/webm' };
      }
    }

    try {
      this.mediaRecorder = new MediaRecorder(stream, options);
    } catch (e) {
      console.warn('Fallback to default MediaRecorder configuration', e);
      this.mediaRecorder = new MediaRecorder(stream);
    }

    this.recordedChunks = [];
    this.mediaRecorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) {
        this.recordedChunks.push(e.data);
      }
    };

    this.mediaRecorder.onstop = () => {
      this.saveFile(preset);
      this.isRecording = false;
      if (this.banner) this.banner.classList.add('hidden');
    };

    // Reset animation to 0 and begin recording
    this.isRecording = true;
    if (this.banner) this.banner.classList.remove('hidden');
    this.engine.seek(0);
    this.engine.pause();

    this.mediaRecorder.start(200);
    this.engine.play();

    // Check interval to automatically stop at exactly 24.0 seconds
    const checkInterval = setInterval(() => {
      if (!this.isRecording) {
        clearInterval(checkInterval);
        return;
      }
      
      const currentTime = this.engine.currentTime;
      if (this.statusText) {
        this.statusText.textContent = `${currentTime.toFixed(1)}s / 24.0s`;
      }

      if (currentTime >= 24.0) {
        clearInterval(checkInterval);
        this.engine.pause();
        this.mediaRecorder.stop();
      }
    }, 100);
  }

  saveFile(preset) {
    const blob = new Blob(this.recordedChunks, { type: 'video/webm' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.style.display = 'none';
    const tag = preset === 'high' ? '1440x1920-master' : '1080x1440-social';
    a.download = `upi-offline-mesh-teaser-3x4-${tag}.webm`;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => {
      document.body.removeChild(a);
      window.URL.revokeObjectURL(url);
    }, 1000);
  }
}

window.TeaserRecorder = TeaserRecorder;

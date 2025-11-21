class WebRTCDemo {
  constructor() {
    this.stream = null;
    this.videoElement = null;
    this.captureCanvas = null;
    this.captureContext = null;
    this.isStreaming = false;
    this.init();
  }

  init() {
    // 获取DOM元素
    this.videoElement = document.getElementById('videoElement');
    this.captureCanvas = document.getElementById('captureCanvas');
    if (this.captureCanvas) {
      this.captureContext = this.captureCanvas.getContext('2d');
    }
    // 绑定事件
    this.bindEvents();
    // 检测设备支持
    this.checkWebRTCSupport();
    // 获取设备信息
    this.getDeviceInfo();
  }

  bindEvents() {
    const startBtn = document.getElementById('startBtn');
    const stopBtn = document.getElementById('stopBtn');
    const captureBtn = document.getElementById('captureBtn');
    const downloadBtn = document.getElementById('downloadBtn');
    
    if (startBtn) startBtn.addEventListener('click', () => this.startCamera());
    if (stopBtn) stopBtn.addEventListener('click', () => this.stopCamera());
    if (captureBtn) captureBtn.addEventListener('click', () => this.capturePhoto());
    if (downloadBtn) downloadBtn.addEventListener('click', () => this.downloadPhoto());
    
    // 视频加载完成后更新视频信息
    if (this.videoElement) {
      this.videoElement.addEventListener('loadedmetadata', () => this.updateVideoInfo());
    }
  }

  checkWebRTCSupport() {
    // 检查浏览器是否支持WebRTC
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      this.showError('您的浏览器不支持WebRTC技术，请使用Chrome、Firefox等现代浏览器');
      return false;
    } else {
      // 兼容性处理
      navigator.getUserMedia = navigator.getUserMedia || 
                               navigator.webkitGetUserMedia || 
                               navigator.mozGetUserMedia || 
                               navigator.msGetUserMedia;
      return true;
    }
  }

  async getDeviceInfo() {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const videoDevices = devices.filter(device => device.kind === 'videoinput');
      const audioDevices = devices.filter(device => device.kind === 'audioinput');
      
      console.log('可用摄像头:', videoDevices);
      console.log('可用麦克风:', audioDevices);
      
      // 更新设备信息显示
      const deviceInfoElement = document.getElementById('deviceInfo');
      if (deviceInfoElement) {
        deviceInfoElement.innerHTML = `
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="bg-white p-4 rounded-lg shadow">
              <h4 class="font-semibold text-primary mb-2">
                <i class="fas fa-video mr-2"></i>视频设备(${videoDevices.length})
              </h4>
              ${videoDevices.length > 0 ? 
                videoDevices.map((device, index) => `
                  <div class="flex items-center mb-2">
                    <span class="mr-2">${index + 1}.</span>
                    <span>${device.label || '未知摄像头'}</span>
                  </div>
                `).join('') : 
                '<p class="text-gray-500 text-sm">未检测到视频设备</p>'
              }
            </div>
            <div class="bg-white p-4 rounded-lg shadow">
              <h4 class="font-semibold text-success mb-2">
                <i class="fas fa-microphone mr-2"></i>音频设备(${audioDevices.length})
              </h4>
              ${audioDevices.length > 0 ? 
                audioDevices.map((device, index) => `
                  <div class="flex items-center mb-2">
                    <span class="mr-2">${index + 1}.</span>
                    <span>${device.label || '未知麦克风'}</span>
                  </div>
                `).join('') : 
                '<p class="text-gray-500 text-sm">未检测到音频设备</p>'
              }
            </div>
          </div>
          <div class="mt-4 p-3 bg-info bg-opacity-10 rounded-lg">
            <p class="text-info">
              <i class="fas fa-info-circle mr-2"></i>
              检测到${devices.length}个媒体设备，包括${videoDevices.length}个视频设备和${audioDevices.length}个音频设备
            </p>
          </div>
        `;
      }
    } catch (error) {
      console.error('获取设备信息失败:', error);
      const deviceInfoElement = document.getElementById('deviceInfo');
      if (deviceInfoElement) {
        deviceInfoElement.innerHTML = `
          <div class="alert alert-error">
            <i class="fas fa-exclamation-circle"></i>
            <span>获取设备信息失败: ${error.message}</span>
          </div>
        `;
      }
    }
  }

  async startCamera() {
    try {
      this.updateStatus('正在启动摄像头...', 'loading');
      
      // 设置媒体约束
      const constraints = {
        video: {
          width: { ideal: 1280 },
          height: { ideal: 720 },
          frameRate: { ideal: 30 }
        },
        audio: false // 本演示只获取视频
      };
      
      // 获取媒体流
      this.stream = await navigator.mediaDevices.getUserMedia(constraints);
      
      // 设置视频源
      if (this.videoElement) {
        this.videoElement.srcObject = this.stream;
        this.videoElement.style.display = 'block';
      }
      
      // 隐藏覆盖层
      const videoOverlay = document.getElementById('videoOverlay');
      if (videoOverlay) {
        videoOverlay.style.opacity = '0';
      }
      
      // 更新UI状态
      this.updateButtonStates();
      this.updateStatus('摄像头已启动', 'success');
      this.isStreaming = true;
      
      // 显示成功提示
      this.showToast('摄像头启动成功!', 'success');
    } catch (error) {
      console.error('启动摄像头失败:', error);
      this.handleCameraError(error);
    }
  }

  stopCamera() {
    // 停止所有轨道
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }
    
    // 清除视频源
    if (this.videoElement) {
      this.videoElement.srcObject = null;
      this.videoElement.style.display = 'none';
    }
    
    // 显示覆盖层
    const videoOverlay = document.getElementById('videoOverlay');
    if (videoOverlay) {
      videoOverlay.style.opacity = '1';
    }
    
    // 重置状态
    this.isStreaming = false;
    this.updateStatus('摄像头已停止', 'error');
    this.updateButtonStates();
    
    // 重置视频信息
    this.resetVideoInfo();
    
    // 显示提示
    this.showToast('摄像头已停止', 'info');
  }

  capturePhoto() {
    try {
      if (!this.isStreaming || !this.videoElement || !this.videoElement.videoWidth) {
        this.showToast('请先启动摄像头', 'warning');
        return;
      }
      
      // 设置画布尺寸
      const videoWidth = this.videoElement.videoWidth;
      const videoHeight = this.videoElement.videoHeight;
      
      if (this.captureCanvas) {
        this.captureCanvas.width = videoWidth;
        this.captureCanvas.height = videoHeight;
        
        // 绘制当前视频帧到画布
        this.captureContext.drawImage(this.videoElement, 0, 0, videoWidth, videoHeight);
        
        // 显示拍照结果
        this.captureCanvas.style.display = 'block';
      }
      
      // 启用下载按钮
      const downloadBtn = document.getElementById('downloadBtn');
      if (downloadBtn) {
        downloadBtn.disabled = false;
      }
      
      this.showToast('拍照成功!', 'success');
    } catch (error) {
      console.error('拍照失败:', error);
      this.showToast('拍照失败，请重试', 'error');
    }
  }

  downloadPhoto() {
    try {
      if (!this.captureCanvas) {
        this.showToast('请先拍照', 'warning');
        return;
      }
      
      // 获取图片数据URL
      const dataURL = this.captureCanvas.toDataURL('image/png');
      
      // 创建下载链接
      const link = document.createElement('a');
      link.download = `photo_${new Date().getTime()}.png`;
      link.href = dataURL;
      
      // 触发下载
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      
      this.showToast('图片下载成功!', 'success');
    } catch (error) {
      console.error('下载图片失败:', error);
      this.showToast('下载失败，请重试', 'error');
    }
  }

  updateButtonStates() {
    const startBtn = document.getElementById('startBtn');
    const stopBtn = document.getElementById('stopBtn');
    const captureBtn = document.getElementById('captureBtn');
    const downloadBtn = document.getElementById('downloadBtn');
    
    if (startBtn) startBtn.disabled = this.isStreaming;
    if (stopBtn) stopBtn.disabled = !this.isStreaming;
    if (captureBtn) captureBtn.disabled = !this.isStreaming;
    if (downloadBtn) downloadBtn.disabled = true; // 下载按钮默认禁用，拍照后启用
  }

  updateStatus(message, type = 'info') {
    const statusIndicator = document.getElementById('statusIndicator');
    const videoStatus = document.getElementById('videoStatus');
    
    if (statusIndicator) {
      let badgeClass = 'badge-error';
      let iconClass = 'fas fa-circle';
      
      switch (type) {
        case 'success':
          badgeClass = 'badge-success';
          iconClass = 'fas fa-check-circle';
          break;
        case 'loading':
          badgeClass = 'badge-info';
          iconClass = 'fas fa-spinner fa-spin';
          break;
        case 'error':
          badgeClass = 'badge-error';
          iconClass = 'fas fa-exclamation-circle';
          break;
        default:
          badgeClass = 'badge-info';
          iconClass = 'fas fa-info-circle';
      }
      
      statusIndicator.innerHTML = `
        <div class="flex items-center">
          <span class="${iconClass} ${badgeClass} mr-2"></span>
          <span>${message}</span>
        </div>
      `;
    }
    
    if (videoStatus) {
      videoStatus.textContent = this.isStreaming ? '已连接' : (type === 'loading' ? '连接中!' : '未连接');
    }
  }

  updateVideoInfo() {
    if (!this.videoElement || !this.stream) return;
    
    // 更新分辨率信息
    const resolution = `${this.videoElement.videoWidth}x${this.videoElement.videoHeight}`;
    const resolutionElement = document.getElementById('videoResolution');
    if (resolutionElement) {
      resolutionElement.textContent = resolution;
    }
    
    // 尝试获取帧率信息
    try {
      const videoTracks = this.stream.getVideoTracks();
      if (videoTracks.length > 0) {
        const videoTrack = videoTracks[0];
        const settings = videoTrack.getSettings();
        const frameRate = settings.frameRate || 30;
        const frameRateText = `${Math.round(frameRate)}fps`;
        
        const frameRateElement = document.getElementById('videoFrameRate');
        if (frameRateElement) {
          frameRateElement.textContent = frameRateText;
        }
      }
    } catch (error) {
      console.error('获取视频信息失败:', error);
    }
  }

  resetVideoInfo() {
    const resolutionElement = document.getElementById('videoResolution');
    const frameRateElement = document.getElementById('videoFrameRate');
    const videoStatusElement = document.getElementById('videoStatus');
    
    if (resolutionElement) resolutionElement.textContent = '-';
    if (frameRateElement) frameRateElement.textContent = '-';
    if (videoStatusElement) videoStatusElement.textContent = '待启动';
  }

  handleCameraError(error) {
    let errorMessage = '启动摄像头失败';
    
    if (error.name) {
      switch (error.name) {
        case 'NotAllowedError':
          errorMessage = '用户拒绝了摄像头权限请求';
          break;
        case 'NotFoundError':
          errorMessage = '未找到可用的摄像头设备';
          break;
        case 'NotSupportedError':
          errorMessage = '浏览器不支持指定的媒体类型';
          break;
        case 'TrackStartError':
          errorMessage = '摄像头设备被其他应用占用';
          break;
        case 'OverconstrainedError':
          errorMessage = '摄像头不支持指定的约束条件';
          break;
        default:
          errorMessage = `摄像头启动失败: ${error.message || error.name}`;
      }
    }
    
    this.updateStatus(errorMessage, 'error');
    this.showToast(errorMessage, 'error');
  }

  showToast(message, type = 'info') {
    // 创建toast元素
    const toast = document.createElement('div');
    toast.className = `alert alert-${type} fixed top-4 right-4 z-50 max-w-sm shadow-lg`;
    toast.style.animation = 'slideInRight 0.3s ease-out';
    
    let icon = 'fas fa-info-circle';
    switch (type) {
      case 'success':
        icon = 'fas fa-check-circle';
        break;
      case 'warning':
        icon = 'fas fa-exclamation-circle';
        break;
      case 'error':
        icon = 'fas fa-times-circle';
        break;
    }
    
    toast.innerHTML = `
      <i class="${icon} mr-2"></i>
      <span>${message}</span>
    `;
    
    document.body.appendChild(toast);
    
    // 3秒后自动移除
    setTimeout(() => {
      toast.style.animation = 'slideOutRight 0.3s ease-in';
      setTimeout(() => {
        if (toast.parentNode) {
          toast.parentNode.removeChild(toast);
        }
      }, 300);
    }, 3000);
  }

  showError(message) {
    const deviceInfoElement = document.getElementById('deviceInfo');
    if (deviceInfoElement) {
      deviceInfoElement.innerHTML = `
        <div class="alert alert-error">
          <i class="fas fa-exclamation-circle"></i>
          <span>${message}</span>
        </div>
      `;
    }
  }

  // 添加动画样式
  addAnimationStyles() {
    const style = document.createElement('style');
    style.textContent = `
      @keyframes slideInRight {
        from {
          transform: translateX(100%);
          opacity: 0;
        }
        to {
          transform: translateX(0);
          opacity: 1;
        }
      }
      @keyframes slideOutRight {
        from {
          transform: translateX(0);
          opacity: 1;
        }
        to {
          transform: translateX(100%);
          opacity: 0;
        }
      }
    `;
    document.head.appendChild(style);
  }
}

// 页面加载完成后初始化
function initWebRTC() {
  const demo = new WebRTCDemo();
  demo.addAnimationStyles();
}

document.addEventListener('DOMContentLoaded', initWebRTC);

// 添加平滑滚动效果
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function (e) {
    e.preventDefault();
    const targetId = this.getAttribute('href');
    if (targetId === '#') return;
    
    const target = document.querySelector(targetId);
    if (target) {
      target.scrollIntoView({
        behavior: 'smooth',
        block: 'start'
      });
    }
  });
});
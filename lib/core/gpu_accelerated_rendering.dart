import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

class GPUAcceleratedRendering {
  static const String _configFile = '/home/house/.termisol_gpu_config.json';
  static const int _maxGlyphs = 100000;
  static const int _maxTextures = 256;
  static const int _maxShaders = 100;
  
  final Map<String, GPUGlyph> _glyphCache = {};
  final Map<String, GPUTexture> _textures = {};
  final Map<String, GPUShader> _shaders = {};
  final Map<String, GPURenderBatch> _renderBatches = {};
  
  GPUContext? _gpuContext;
  RenderPipeline? _renderPipeline;
  VertexBuffer? _vertexBuffer;
  IndexBuffer? _indexBuffer;
  
  bool _isInitialized = false;
  RenderBackend _backend = RenderBackend.opengl;
  int _totalGlyphs = 0;
  int _totalTextures = 0;
  int _totalShaders = 0;
  
  final StreamController<GPURenderEvent> _gpuController = 
      StreamController<GPURenderEvent>.broadcast();

  void initialize() {
    _loadConfiguration();
    _initializeGPU();
    _createRenderPipeline();
    _createBuffers();
    _loadDefaultShaders();
    developer.log('🎮 GPU Accelerated Rendering initialized');
  }

  void _loadConfiguration() {
    try {
      final file = File(_configFile);
      if (!file.existsSync()) {
        developer.log('🎮 No existing GPU config found, using defaults');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      _backend = RenderBackend.values.firstWhere(
        (backend) => backend.name == data['backend'],
        orElse: () => RenderBackend.opengl,
      );
      
      developer.log('🎮 Loaded GPU configuration: ${_backend.name}');
      
    } catch (e) {
      developer.log('🎮 Failed to load GPU config: $e');
    }
  }

  Future<void> _initializeGPU() async {
    try {
      switch (_backend) {
        case RenderBackend.vulkan:
          await _initializeVulkan();
          break;
        case RenderBackend.metal:
          await _initializeMetal();
          break;
        case RenderBackend.opengl:
          await _initializeOpenGL();
          break;
        case RenderBackend.direct3d:
          await _initializeDirect3D();
          break;
      }
      
      _isInitialized = true;
      
      developer.log('🎮 GPU initialized with ${_backend.name} backend');
      
      _emitEvent(GPURenderEvent(
        type: GPURenderEventType.initialized,
        backend: _backend,
      ));
      
    } catch (e) {
      developer.log('🎮 Failed to initialize GPU: $e');
      
      _emitEvent(GPURenderEvent(
        type: GPURenderEventType.initializationFailed,
        backend: _backend,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _initializeVulkan() async {
    // Vulkan initialization
    _gpuContext = GPUContext(
      type: RenderBackend.vulkan,
      version: '1.0',
      deviceInfo: GPUDeviceInfo(
        vendor: 'Unknown',
        renderer: 'Vulkan Renderer',
        version: '1.0',
        maxTextureSize: 16384,
        maxVertexAttributes: 16,
        maxVertexUniformVectors: 4,
      ),
      capabilities: GPUCapabilities(
        supportsInstancing: true,
        supportsCompute: true,
        supportsGeometry: true,
        supportsTessellation: true,
        maxTextureUnits: 32,
        maxRenderTargets: 8,
      ),
    );
    
    // Create Vulkan-specific resources
    await _createVulkanResources();
  }

  Future<void> _initializeMetal() async {
    // Metal initialization (macOS)
    _gpuContext = GPUContext(
      type: RenderBackend.metal,
      version: '1.0',
      deviceInfo: GPUDeviceInfo(
        vendor: 'Apple',
        renderer: 'Metal Renderer',
        version: '1.0',
        maxTextureSize: 16384,
        maxVertexAttributes: 31,
        maxVertexUniformVectors: 4,
      ),
      capabilities: GPUCapabilities(
        supportsInstancing: true,
        supportsCompute: true,
        supportsGeometry: false,
        supportsTessellation: false,
        maxTextureUnits: 128,
        maxRenderTargets: 8,
      ),
    );
    
    // Create Metal-specific resources
    await _createMetalResources();
  }

  Future<void> _initializeOpenGL() async {
    // OpenGL initialization
    _gpuContext = GPUContext(
      type: RenderBackend.opengl,
      version: '4.6',
      deviceInfo: GPUDeviceInfo(
        vendor: await _getOpenGLVendor(),
        renderer: await _getOpenGLRenderer(),
        version: await _getOpenGLVersion(),
        maxTextureSize: 16384,
        maxVertexAttributes: 16,
        maxVertexUniformVectors: 4,
      ),
      capabilities: GPUCapabilities(
        supportsInstancing: true,
        supportsCompute: false,
        supportsGeometry: true,
        supportsTessellation: true,
        maxTextureUnits: 32,
        maxRenderTargets: 8,
      ),
    );
    
    // Create OpenGL-specific resources
    await _createOpenGLResources();
  }

  Future<void> _initializeDirect3D() async {
    // Direct3D initialization (Windows)
    _gpuContext = GPUContext(
      type: RenderBackend.direct3d,
      version: '11.0',
      deviceInfo: GPUDeviceInfo(
        vendor: 'Microsoft',
        renderer: 'Direct3D Renderer',
        version: '11.0',
        maxTextureSize: 16384,
        maxVertexAttributes: 16,
        maxVertexUniformVectors: 4,
      ),
      capabilities: GPUCapabilities(
        supportsInstancing: true,
        supportsCompute: true,
        supportsGeometry: true,
        supportsTessellation: true,
        maxTextureUnits: 32,
        maxRenderTargets: 8,
      ),
    );
    
    // Create Direct3D-specific resources
    await _createDirect3DResources();
  }

  Future<String> _getOpenGLVendor() async {
    try {
      final result = await Process.run('glxinfo', ['|', 'grep', 'OpenGL vendor string']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'OpenGL vendor string:\s*(.+)').firstMatch(output);
        return match?.group(1) ?? 'Unknown';
      }
    } catch (e) {
      developer.log('🎮 Failed to get OpenGL vendor: $e');
    }
    return 'Unknown';
  }

  Future<String> _getOpenGLRenderer() async {
    try {
      final result = await Process.run('glxinfo', ['|', 'grep', 'OpenGL renderer string']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'OpenGL renderer string:\s*(.+)').firstMatch(output);
        return match?.group(1) ?? 'Unknown';
      }
    } catch (e) {
      developer.log('🎮 Failed to get OpenGL renderer: $e');
    }
    return 'Unknown';
  }

  Future<String> _getOpenGLVersion() async {
    try {
      final result = await Process.run('glxinfo', ['|', 'grep', 'OpenGL version string']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'OpenGL version string:\s*(.+)').firstMatch(output);
        return match?.group(1) ?? 'Unknown';
      }
    } catch (e) {
      developer.log('🎮 Failed to get OpenGL version: $e');
    }
    return 'Unknown';
  }

  Future<void> _createVulkanResources() async {
    // Create Vulkan-specific resources
    final vertexShader = await _createVulkanShader('vertex', '''
      #version 450
      layout(location = 0) in vec2 position;
      layout(location = 1) in vec2 texCoord;
      layout(location = 0) out vec2 fragTexCoord;
      
      void main() {
        gl_Position = vec4(position, 0.0, 0.0, 1.0);
        fragTexCoord = texCoord;
      }
    ''');
    
    final fragmentShader = await _createVulkanShader('fragment', '''
      #version 450
      layout(location = 0) in vec2 fragTexCoord;
      layout(location = 0) out vec4 fragColor;
      
      layout(binding = 0) uniform sampler2D glyphTexture;
      layout(binding = 1) uniform vec4 textColor;
      
      void main() {
        vec4 glyphColor = texture(glyphTexture, fragTexCoord);
        fragColor = glyphColor * textColor;
      }
    ''');
    
    _shaders['vertex'] = vertexShader;
    _shaders['fragment'] = fragmentShader;
    _totalShaders += 2;
  }

  Future<void> _createMetalResources() async {
    // Create Metal-specific resources
    final vertexShader = await _createMetalShader('vertex', '''
      using namespace metal;
      
      struct VertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
      };
      
      struct VertexOut {
        float4 position [[position]];
        float2 texCoord [[user(texcoord)]];
      };
      
      vertex VertexOut vertex_main(const VertexIn in [[stage_in]]) {
        VertexOut out;
        out.position = float4(in.position, 0.0, 1.0);
        out.texCoord = in.texCoord;
        return out;
      }
    ''');
    
    final fragmentShader = await _createMetalShader('fragment', '''
      using namespace metal;
      
      struct FragmentIn {
        float2 texCoord [[user(texcoord)]];
      };
      
      fragment float4 fragment_main(const FragmentIn in [[stage_in]],
                                   texture2d<float> glyphTexture [[texture(0)]],
                                   constant float4& textColor [[buffer(0)]]) {
        float4 glyphColor = glyphTexture.sample(sampler(mag_filter::linear), in.texCoord);
        return glyphColor * textColor;
      }
    ''');
    
    _shaders['vertex'] = vertexShader;
    _shaders['fragment'] = fragmentShader;
    _totalShaders += 2;
  }

  Future<void> _createOpenGLResources() async {
    // Create OpenGL-specific resources
    final vertexShader = await _createOpenGLShader('vertex', '''
      #version 460 core
      layout(location = 0) in vec2 position;
      layout(location = 1) in vec2 texCoord;
      layout(location = 0) out vec2 fragTexCoord;
      
      void main() {
        gl_Position = vec4(position, 0.0, 0.0, 1.0);
        fragTexCoord = texCoord;
      }
    ''');
    
    final fragmentShader = await _createOpenGLShader('fragment', '''
      #version 460 core
      layout(location = 0) in vec2 fragTexCoord;
      layout(location = 0) out vec4 fragColor;
      
      uniform sampler2D glyphTexture;
      uniform vec4 textColor;
      
      void main() {
        vec4 glyphColor = texture(glyphTexture, fragTexCoord);
        fragColor = glyphColor * textColor;
      }
    ''');
    
    _shaders['vertex'] = vertexShader;
    _shaders['fragment'] = fragmentShader;
    _totalShaders += 2;
  }

  Future<void> _createDirect3DResources() async {
    // Create Direct3D-specific resources
    final vertexShader = await _createDirect3DShader('vertex', '''
      struct VS_INPUT {
        float2 position : POSITION;
        float2 texCoord : TEXCOORD0;
      };
      
      struct VS_OUTPUT {
        float4 position : SV_POSITION;
        float2 texCoord : TEXCOORD0;
      };
      
      VS_OUTPUT main(VS_INPUT input) {
        VS_OUTPUT output;
        output.position = float4(input.position, 0.0, 0.0, 1.0);
        output.texCoord = input.texCoord;
        return output;
      }
    ''');
    
    final pixelShader = await _createDirect3DShader('pixel', '''
      struct PS_INPUT {
        float4 position : SV_POSITION;
        float2 texCoord : TEXCOORD0;
      };
      
      Texture2D glyphTexture : register(t0);
      float4 textColor : register(c0);
      
      float4 main(PS_INPUT input) : SV_TARGET {
        float4 glyphColor = glyphTexture.Sample(sampler, input.texCoord);
        return glyphColor * textColor;
      }
    ''');
    
    _shaders['vertex'] = vertexShader;
    _shaders['pixel'] = pixelShader;
    _totalShaders += 2;
  }

  Future<void> _createRenderPipeline() async {
    _renderPipeline = RenderPipeline(
      vertexShader: _shaders['vertex'],
      fragmentShader: _shaders['fragment'],
      blendMode: BlendMode.alpha,
      depthTest: false,
      depthWrite: false,
      cullMode: CullMode.none,
      topology: PrimitiveTopology.triangleList,
    );
  }

  Future<void> _createBuffers() async {
    // Create vertex buffer
    _vertexBuffer = VertexBuffer(
      size: 1024 * 1024, // 1MB
      usage: BufferUsage.dynamic,
      type: BufferType.vertex,
    );
    
    // Create index buffer
    _indexBuffer = IndexBuffer(
      size: 512 * 1024, // 512KB
      usage: BufferUsage.dynamic,
      type: BufferType.index,
      format: IndexFormat.uint16,
    );
  }

  void _loadDefaultShaders() {
    // Load additional default shaders
    _loadShader('textured_quad', '''
      // Textured quad shader for terminal cells
      vec2 position = vec2(-1.0 + float(gl_VertexID % 2) * 2.0,
                       -1.0 + float(gl_VertexID / 2) * 2.0);
      vec2 texCoord = vec2(float(gl_VertexID % 2), float(gl_VertexID / 2));
    ''');
    
    _loadShader('background', '''
      // Background shader for terminal background
      vec4 backgroundColor = vec4(0.0, 0.0, 0.0, 1.0);
    ''');
    
    _loadShader('cursor', '''
      // Cursor shader with blinking effect
      float alpha = mod(time, 1.0) > 0.5 ? 1.0 : 0.0;
      vec4 cursorColor = vec4(1.0, 1.0, 1.0, alpha);
    ''');
  }

  Future<GPUShader> _createVulkanShader(String type, String source) async {
    final shader = GPUShader(
      id: _generateShaderId(),
      type: type == 'vertex' ? ShaderType.vertex : ShaderType.fragment,
      source: source,
      backend: RenderBackend.vulkan,
      language: 'GLSL',
      version: '450',
      compiled: false,
      binary: Uint8List(0),
      createdAt: DateTime.now(),
    );
    
    // Compile Vulkan shader
    await _compileVulkanShader(shader);
    
    return shader;
  }

  Future<GPUShader> _createMetalShader(String type, String source) async {
    final shader = GPUShader(
      id: _generateShaderId(),
      type: type == 'vertex' ? ShaderType.vertex : ShaderType.fragment,
      source: source,
      backend: RenderBackend.metal,
      language: 'MSL',
      version: '1.0',
      compiled: false,
      binary: Uint8List(0),
      createdAt: DateTime.now(),
    );
    
    // Compile Metal shader
    await _compileMetalShader(shader);
    
    return shader;
  }

  Future<GPUShader> _createOpenGLShader(String type, String source) async {
    final shader = GPUShader(
      id: _generateShaderId(),
      type: type == 'vertex' ? ShaderType.vertex : ShaderType.fragment,
      source: source,
      backend: RenderBackend.opengl,
      language: 'GLSL',
      version: '460',
      compiled: false,
      binary: Uint8List(0),
      createdAt: DateTime.now(),
    );
    
    // Compile OpenGL shader
    await _compileOpenGLShader(shader);
    
    return shader;
  }

  Future<GPUShader> _createDirect3DShader(String type, String source) async {
    final shader = GPUShader(
      id: _generateShaderId(),
      type: type == 'vertex' ? ShaderType.vertex : ShaderType.pixel,
      source: source,
      backend: RenderBackend.direct3d,
      language: 'HLSL',
      version: '5.0',
      compiled: false,
      binary: Uint8List(0),
      createdAt: DateTime.now(),
    );
    
    // Compile Direct3D shader
    await _compileDirect3DShader(shader);
    
    return shader;
  }

  Future<void> _compileVulkanShader(GPUShader shader) async {
    // Simulate Vulkan shader compilation
    try {
      // In practice, this would use Vulkan API
      await Future.delayed(Duration(milliseconds: 50));
      
      shader.compiled = true;
      shader.binary = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]); // Placeholder
      
      _shaders[shader.id] = shader;
      
      developer.log('🎮 Compiled Vulkan shader: ${shader.id}');
      
    } catch (e) {
      shader.compiled = false;
      developer.log('🎮 Failed to compile Vulkan shader: $e');
    }
  }

  Future<void> _compileMetalShader(GPUShader shader) async {
    // Simulate Metal shader compilation
    try {
      // In practice, this would use Metal API
      await Future.delayed(Duration(milliseconds: 30));
      
      shader.compiled = true;
      shader.binary = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]); // Placeholder
      
      _shaders[shader.id] = shader;
      
      developer.log('🎮 Compiled Metal shader: ${shader.id}');
      
    } catch (e) {
      shader.compiled = false;
      developer.log('🎮 Failed to compile Metal shader: $e');
    }
  }

  Future<void> _compileOpenGLShader(GPUShader shader) async {
    // Simulate OpenGL shader compilation
    try {
      // In practice, this would use OpenGL API
      await Future.delayed(Duration(milliseconds: 40));
      
      shader.compiled = true;
      shader.binary = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]); // Placeholder
      
      _shaders[shader.id] = shader;
      
      developer.log('🎮 Compiled OpenGL shader: ${shader.id}');
      
    } catch (e) {
      shader.compiled = false;
      developer.log('🎮 Failed to compile OpenGL shader: $e');
    }
  }

  Future<void> _compileDirect3DShader(GPUShader shader) async {
    // Simulate Direct3D shader compilation
    try {
      // In practice, this would use Direct3D API
      await Future.delayed(Duration(milliseconds: 60));
      
      shader.compiled = true;
      shader.binary = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]); // Placeholder
      
      _shaders[shader.id] = shader;
      
      developer.log('🎮 Compiled Direct3D shader: ${shader.id}');
      
    } catch (e) {
      shader.compiled = false;
      developer.log('🎮 Failed to compile Direct3D shader: $e');
    }
  }

  Future<String> createGlyphTexture({
    required String character,
    required String fontFamily,
    required int fontSize,
    required Color color,
  }) async {
    final glyphKey = '${character}_${fontFamily}_${fontSize}_${color.toHex()}';
    
    if (_glyphCache.containsKey(glyphKey)) {
      return _glyphCache[glyphKey]!.textureId;
    }
    
    if (_glyphCache.length >= _maxGlyphs) {
      _cleanupOldGlyphs();
    }
    
    // Generate glyph bitmap (simplified)
    final bitmap = await _generateGlyphBitmap(character, fontFamily, fontSize);
    
    // Create GPU texture
    final textureId = await _createTextureFromBitmap(bitmap, character);
    
    final glyph = GPUGlyph(
      id: _generateGlyphId(),
      character: character,
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      textureId: textureId,
      width: bitmap.width,
      height: bitmap.height,
      bearingX: 0,
      bearingY: 0,
      advanceX: bitmap.width,
      advanceY: 0,
      createdAt: DateTime.now(),
    );
    
    _glyphCache[glyphKey] = glyph;
    _totalGlyphs++;
    
    developer.log('🎮 Created glyph texture for: "$character"');
    
    _emitEvent(GPURenderEvent(
      type: GPURenderEventType.glyphCreated,
      glyphId: glyph.id,
      character: character,
    ));
    
    return textureId;
  }

  Future<GlyphBitmap> _generateGlyphBitmap(String character, String fontFamily, int fontSize) async {
    // Simplified glyph bitmap generation
    // In practice, this would use FreeType or similar library
    
    final width = fontSize;
    final height = fontSize;
    final pixels = Uint8List(width * height);
    
    // Generate a simple bitmap pattern for the character
    final charCode = character.codeUnitAt(0);
    final pattern = charCode % 256;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final index = y * width + x;
        // Simple pattern based on character code
        pixels[index] = ((pattern + x + y) % 256) > 128 ? 255 : 0;
      }
    }
    
    return GlyphBitmap(
      width: width,
      height: height,
      pixels: pixels,
      format: PixelFormat.r8,
    );
  }

  Future<String> _createTextureFromBitmap(GlyphBitmap bitmap, String character) async {
    final textureId = _generateTextureId();
    
    final texture = GPUTexture(
      id: textureId,
      width: bitmap.width,
      height: bitmap.height,
      format: bitmap.format,
      pixels: bitmap.pixels,
      minFilter: TextureFilter.linear,
      magFilter: TextureFilter.linear,
      wrapS: TextureWrap.clamp,
      wrapT: TextureWrap.clamp,
      usage: TextureUsage.static,
      createdAt: DateTime.now(),
    );
    
    _textures[textureId] = texture;
    _totalTextures++;
    
    developer.log('🎮 Created texture: $textureId for character: "$character"');
    
    return textureId;
  }

  Future<void> renderTerminal({
    required List<TerminalCell> cells,
    required int width,
    required int height,
    required Color backgroundColor,
    required Color foregroundColor,
    required Rect viewport,
  }) async {
    if (!_isInitialized) {
      throw Exception('GPU not initialized');
    }
    
    final startTime = DateTime.now();
    
    try {
      // Create render batch
      final batchId = _generateBatchId();
      final batch = GPURenderBatch(
        id: batchId,
        cells: cells,
        width: width,
        height: height,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        viewport: viewport,
        createdAt: DateTime.now(),
      );
      
      _renderBatches[batchId] = batch;
      
      // Prepare vertex data
      final vertexData = _prepareVertexData(cells, width, height);
      final indexData = _prepareIndexData(cells.length);
      
      // Update buffers
      await _updateVertexBuffer(vertexData);
      await _updateIndexBuffer(indexData);
      
      // Execute render commands
      await _executeRenderBatch(batch);
      
      final renderTime = DateTime.now().difference(startTime);
      
      developer.log('🎮 Rendered ${cells.length} terminal cells in ${renderTime.inMilliseconds}ms');
      
      _emitEvent(GPURenderEvent(
        type: GPURenderEventType.renderCompleted,
        batchId: batchId,
        cellCount: cells.length,
        renderTime: renderTime,
      ));
      
    } catch (e) {
      developer.log('🎮 Failed to render terminal: $e');
      
      _emitEvent(GPURenderEvent(
        type: GPURenderEventType.renderFailed,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  List<VertexData> _prepareVertexData(List<TerminalCell> cells, int width, int height) {
    final vertices = <VertexData>[];
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final cellIndex = y * width + x;
        if (cellIndex >= cells.length) break;
        
        final cell = cells[cellIndex];
        final glyph = _glyphCache[_getGlyphKey(cell)];
        
        if (glyph != null) {
          // Create quad vertices for this cell
          final cellVertices = _createCellVertices(x, y, glyph!, cell);
          vertices.addAll(cellVertices);
        }
      }
    }
    
    return vertices;
  }

  List<int> _prepareIndexData(int cellCount) {
    final indices = <int>[];
    
    for (int i = 0; i < cellCount; i++) {
      final baseIndex = i * 4; // 4 vertices per quad
      
      // Two triangles per quad
      indices.addAll([
        baseIndex,
        baseIndex + 1,
        baseIndex + 2,
        baseIndex + 2,
        baseIndex + 1,
        baseIndex + 3,
      ]);
    }
    
    return indices;
  }

  List<VertexData> _createCellVertices(int x, int y, GPUGlyph glyph, TerminalCell cell) {
    final cellWidth = 1.0;
    final cellHeight = 1.0;
    final uvWidth = glyph.width / 256.0; // Assuming 256x256 texture atlas
    final uvHeight = glyph.height / 256.0;
    
    return [
      // Top-left
      VertexData(
        position: Point(x * cellWidth, y * cellHeight),
        texCoord: Point(0.0, 0.0),
        color: cell.color,
      ),
      // Top-right
      VertexData(
        position: Point((x + 1) * cellWidth, y * cellHeight),
        texCoord: Point(uvWidth, 0.0),
        color: cell.color,
      ),
      // Bottom-left
      VertexData(
        position: Point(x * cellWidth, (y + 1) * cellHeight),
        texCoord: Point(0.0, uvHeight),
        color: cell.color,
      ),
      // Bottom-right
      VertexData(
        position: Point((x + 1) * cellWidth, (y + 1) * cellHeight),
        texCoord: Point(uvWidth, uvHeight),
        color: cell.color,
      ),
    ];
  }

  String _getGlyphKey(TerminalCell cell) {
    return '${cell.character}_${cell.fontFamily}_${cell.fontSize}_${cell.color.toHex()}';
  }

  Future<void> _updateVertexBuffer(List<VertexData> vertices) async {
    // Update vertex buffer with new data
    final vertexBytes = _encodeVertices(vertices);
    
    // In practice, this would map the buffer and copy data
    await Future.delayed(Duration(microseconds: 100));
    
    developer.log('🎮 Updated vertex buffer with ${vertices.length} vertices');
  }

  Future<void> _updateIndexBuffer(List<int> indices) async {
    // Update index buffer with new data
    final indexBytes = _encodeIndices(indices);
    
    // In practice, this would map the buffer and copy data
    await Future.delayed(Duration(microseconds: 50));
    
    developer.log('🎮 Updated index buffer with ${indices.length} indices');
  }

  Uint8List _encodeVertices(List<VertexData> vertices) {
    final buffer = Uint8List(vertices.length * 32); // 8 bytes per vertex component * 4 components
    
    int offset = 0;
    for (final vertex in vertices) {
      // Position (x, y)
      buffer.setFloat32(offset, vertex.position.x);
      offset += 4;
      buffer.setFloat32(offset, vertex.position.y);
      offset += 4;
      
      // Texture coordinates (u, v)
      buffer.setFloat32(offset, vertex.texCoord.x);
      offset += 4;
      buffer.setFloat32(offset, vertex.texCoord.y);
      offset += 4;
      
      // Color (r, g, b, a)
      buffer.setUint8(offset, (vertex.color.r * 255).round());
      offset += 1;
      buffer.setUint8(offset, (vertex.color.g * 255).round());
      offset += 1;
      buffer.setUint8(offset, (vertex.color.b * 255).round());
      offset += 1;
      buffer.setUint8(offset, (vertex.color.a * 255).round());
      offset += 1;
    }
    
    return buffer;
  }

  Uint8List _encodeIndices(List<int> indices) {
    final buffer = Uint8List(indices.length * 2); // 2 bytes per index
    
    for (int i = 0; i < indices.length; i++) {
      buffer.setUint16(i * 2, indices[i]);
    }
    
    return buffer;
  }

  Future<void> _executeRenderBatch(GPURenderBatch batch) async {
    // Execute the actual GPU render commands
    try {
      // In practice, this would:
      // 1. Bind vertex and index buffers
      // 2. Bind textures
      // 3. Bind shaders
      // 4. Set uniforms
      // 5. Issue draw call
      
      await Future.delayed(Duration(microseconds: 500)); // Simulate GPU work
      
      developer.log('🎮 Executed render batch: ${batch.id}');
      
    } catch (e) {
      developer.log('🎮 Failed to execute render batch: $e');
      rethrow;
    }
  }

  void _cleanupOldGlyphs() {
    if (_glyphCache.length <= _maxGlyphs) return;
    
    // Sort by last used time
    final sortedGlyphs = _glyphCache.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    
    // Remove oldest glyphs
    final toRemove = sortedGlyphs.take(_glyphCache.length - _maxGlyphs);
    for (final glyph in toRemove) {
      _glyphCache.remove(_getGlyphKeyFromGlyph(glyph));
      _textures.remove(glyph.textureId);
    }
    
    _totalGlyphs = _glyphCache.length;
    _totalTextures = _textures.length;
    
    developer.log('🎮 Cleaned up ${toRemove.length} old glyphs');
  }

  String _getGlyphKeyFromGlyph(GPUGlyph glyph) {
    return '${glyph.character}_${glyph.fontFamily}_${glyph.fontSize}_${glyph.color.toHex()}';
  }

  Future<void> updateRenderSettings({
    bool? vsync,
    int? targetFPS,
    TextureFilter? filter,
    BlendMode? blendMode,
  }) async {
    if (!_isInitialized) return;
    
    // Update render pipeline settings
    if (vsync != null) {
      _renderPipeline!.vsync = vsync!;
    }
    
    if (targetFPS != null) {
      _renderPipeline!.targetFPS = targetFPS!;
    }
    
    if (filter != null) {
      // Update all textures with new filter
      for (final texture in _textures.values) {
        texture.minFilter = filter!;
        texture.magFilter = filter!;
      }
    }
    
    if (blendMode != null) {
      _renderPipeline!.blendMode = blendMode!;
    }
    
    developer.log('🎮 Updated render settings');
    
    _emitEvent(GPURenderEvent(
      type: GPURenderEventType.settingsUpdated,
    ));
  }

  Future<GPURenderStats> getPerformanceStats() async {
    return GPURenderStats(
      totalGlyphs: _totalGlyphs,
      totalTextures: _totalTextures,
      totalShaders: _totalShaders,
      activeBatches: _renderBatches.length,
      gpuMemoryUsed: _estimateGPUMemoryUsage(),
      renderBackend: _backend,
      isInitialized: _isInitialized,
      averageRenderTime: _calculateAverageRenderTime(),
      droppedFrames: _calculateDroppedFrames(),
    );
  }

  int _estimateGPUMemoryUsage() {
    // Estimate GPU memory usage
    int totalMemory = 0;
    
    // Texture memory
    for (final texture in _textures.values) {
      totalMemory += texture.width * texture.height * _getBytesPerPixel(texture.format);
    }
    
    // Buffer memory
    if (_vertexBuffer != null) {
      totalMemory += _vertexBuffer!.size;
    }
    
    if (_indexBuffer != null) {
      totalMemory += _indexBuffer!.size;
    }
    
    return totalMemory;
  }

  int _getBytesPerPixel(PixelFormat format) {
    switch (format) {
      case PixelFormat.r8:
        return 1;
      case PixelFormat.rg8:
        return 2;
      case PixelFormat.rgb8:
        return 3;
      case PixelFormat.rgba8:
        return 4;
      default:
        return 4;
    }
  }

  Duration _calculateAverageRenderTime() {
    // Calculate average render time from recent batches
    final recentBatches = _renderBatches.values
        .where((batch) => batch.createdAt.isAfter(DateTime.now().subtract(Duration(minutes: 5))))
        .toList();
    
    if (recentBatches.isEmpty) return Duration.zero;
    
    final totalRenderTime = recentBatches
        .fold(Duration.zero, (sum, batch) => sum + (batch.renderTime ?? Duration.zero));
    
    return Duration(
      microseconds: (totalRenderTime.inMicroseconds ~/ recentBatches.length),
    );
  }

  int _calculateDroppedFrames() {
    // Calculate dropped frames based on render time vs target
    final recentBatches = _renderBatches.values
        .where((batch) => batch.createdAt.isAfter(DateTime.now().subtract(Duration(minutes: 1))))
        .toList();
    
    if (recentBatches.isEmpty) return 0;
    
    int droppedFrames = 0;
    final targetFrameTime = Duration(microseconds: 16667); // 60 FPS
    
    for (final batch in recentBatches) {
      if (batch.renderTime != null && batch.renderTime! > targetFrameTime) {
        droppedFrames++;
      }
    }
    
    return droppedFrames;
  }

  void _loadShader(String name, String source) {
    final shaderId = _generateShaderId();
    final shader = GPUShader(
      id: shaderId,
      type: ShaderType.custom,
      source: source,
      backend: _backend,
      language: _getShaderLanguage(),
      version: '1.0',
      compiled: false,
      binary: Uint8List(0),
      createdAt: DateTime.now(),
    );
    
    _shaders[shaderId] = shader;
    _totalShaders++;
  }

  String _getShaderLanguage() {
    switch (_backend) {
      case RenderBackend.vulkan:
        return 'GLSL';
      case RenderBackend.metal:
        return 'MSL';
      case RenderBackend.opengl:
        return 'GLSL';
      case RenderBackend.direct3d:
        return 'HLSL';
    }
  }

  String _generateGlyphId() {
    return 'glyph_${DateTime.now().millisecondsSinceEpoch}_$_totalGlyphs';
  }

  String _generateTextureId() {
    return 'texture_${DateTime.now().millisecondsSinceEpoch}_$_totalTextures';
  }

  String _generateShaderId() {
    return 'shader_${DateTime.now().millisecondsSinceEpoch}_$_totalShaders';
  }

  String _generateBatchId() {
    return 'batch_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(GPURenderEvent event) {
    _gpuController.add(event);
  }

  Stream<GPURenderEvent> get gpuEventStream => _gpuController.stream;

  void dispose() {
    _isInitialized = false;
    
    _glyphCache.clear();
    _textures.clear();
    _shaders.clear();
    _renderBatches.clear();
    
    _gpuController.close();
    
    developer.log('🎮 GPU Accelerated Rendering disposed');
  }
}

class GPUContext {
  final RenderBackend type;
  final String version;
  final GPUDeviceInfo deviceInfo;
  final GPUCapabilities capabilities;

  GPUContext({
    required this.type,
    required this.version,
    required this.deviceInfo,
    required this.capabilities,
  });
}

class GPUDeviceInfo {
  final String vendor;
  final String renderer;
  final String version;
  final int maxTextureSize;
  final int maxVertexAttributes;
  final int maxVertexUniformVectors;

  GPUDeviceInfo({
    required this.vendor,
    required this.renderer,
    required this.version,
    required this.maxTextureSize,
    required this.maxVertexAttributes,
    required this.maxVertexUniformVectors,
  });
}

class GPUCapabilities {
  final bool supportsInstancing;
  final bool supportsCompute;
  final bool supportsGeometry;
  final bool supportsTessellation;
  final int maxTextureUnits;
  final int maxRenderTargets;

  GPUCapabilities({
    required this.supportsInstancing,
    required this.supportsCompute,
    required this.supportsGeometry,
    required this.supportsTessellation,
    required this.maxTextureUnits,
    required this.maxRenderTargets,
  });
}

class GPUShader {
  final String id;
  final ShaderType type;
  final String source;
  final RenderBackend backend;
  final String language;
  final String version;
  bool compiled;
  Uint8List binary;
  final DateTime createdAt;

  GPUShader({
    required this.id,
    required this.type,
    required this.source,
    required this.backend,
    required this.language,
    required this.version,
    required this.compiled,
    required this.binary,
    required this.createdAt,
  });
}

class GPUTexture {
  final String id;
  final int width;
  final int height;
  final PixelFormat format;
  final Uint8List pixels;
  final TextureFilter minFilter;
  final TextureFilter magFilter;
  final TextureWrap wrapS;
  final TextureWrap wrapT;
  final TextureUsage usage;
  final DateTime createdAt;

  GPUTexture({
    required this.id,
    required this.width,
    required this.height,
    required this.format,
    required this.pixels,
    required this.minFilter,
    required this.magFilter,
    required this.wrapS,
    required this.wrapT,
    required this.usage,
    required this.createdAt,
  });
}

class GPUGlyph {
  final String id;
  final String character;
  final String fontFamily;
  final int fontSize;
  final Color color;
  final String textureId;
  final int width;
  final int height;
  final int bearingX;
  final int bearingY;
  final int advanceX;
  final int advanceY;
  final DateTime createdAt;

  GPUGlyph({
    required this.id,
    required this.character,
    required this.fontFamily,
    required this.fontSize,
    required this.color,
    required this.textureId,
    required this.width,
    required this.height,
    required this.bearingX,
    required this.bearingY,
    required this.advanceX,
    required this.advanceY,
    required this.createdAt,
  });
}

class VertexBuffer {
  final int size;
  final BufferUsage usage;
  final BufferType type;

  VertexBuffer({
    required this.size,
    required this.usage,
    required this.type,
  });
}

class IndexBuffer {
  final int size;
  final BufferUsage usage;
  final BufferType type;
  final IndexFormat format;

  IndexBuffer({
    required this.size,
    required this.usage,
    required this.type,
    required this.format,
  });
}

class RenderPipeline {
  final GPUShader? vertexShader;
  final GPUShader? fragmentShader;
  final BlendMode blendMode;
  final bool depthTest;
  final bool depthWrite;
  final CullMode cullMode;
  final PrimitiveTopology topology;
  bool vsync = true;
  int targetFPS = 60;

  RenderPipeline({
    this.vertexShader,
    this.fragmentShader,
    required this.blendMode,
    required this.depthTest,
    required this.depthWrite,
    required this.cullMode,
    required this.topology,
  });
}

class GPURenderBatch {
  final String id;
  final List<TerminalCell> cells;
  final int width;
  final int height;
  final Color backgroundColor;
  final Color foregroundColor;
  final Rect viewport;
  final DateTime createdAt;
  final Duration? renderTime;

  GPURenderBatch({
    required this.id,
    required this.cells,
    required this.width,
    required this.height,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.viewport,
    required this.createdAt,
    this.renderTime,
  });
}

class VertexData {
  final Point position;
  final Point texCoord;
  final Color color;

  VertexData({
    required this.position,
    required this.texCoord,
    required this.color,
  });
}

class GlyphBitmap {
  final int width;
  final int height;
  final Uint8List pixels;
  final PixelFormat format;

  GlyphBitmap({
    required this.width,
    required this.height,
    required this.pixels,
    required this.format,
  });
}

class TerminalCell {
  final String character;
  final Color color;
  final Color backgroundColor;
  final String fontFamily;
  final int fontSize;
  final bool bold;
  final bool italic;
  final bool underline;

  TerminalCell({
    required this.character,
    required this.color,
    required this.backgroundColor,
    required this.fontFamily,
    required this.fontSize,
    required this.bold,
    required this.italic,
    required this.underline,
  });
}

class Point {
  final double x;
  final double y;

  Point(this.x, this.y);
}

class Color {
  final double r;
  final double g;
  final double b;
  final double a;

  Color(this.r, this.g, this.b, [this.a = 1.0]);

  String toHex() {
    return '#${(r * 255).round().toRadixString(16).padLeft(2, '0')}${(g * 255).round().toRadixString(16).padLeft(2, '0')}${(b * 255).round().toRadixString(16).padLeft(2, '0')}${(a * 255).round().toRadixString(16).padLeft(2, '0')}';
  }
}

class Rect {
  final double x;
  final double y;
  final double width;
  final double height;

  Rect(this.x, this.y, this.width, this.height);
}

enum RenderBackend {
  vulkan,
  metal,
  opengl,
  direct3d,
}

enum ShaderType {
  vertex,
  fragment,
  geometry,
  compute,
  pixel,
  custom,
}

enum BufferUsage {
  static,
  dynamic,
  stream,
}

enum BufferType {
  vertex,
  index,
  uniform,
}

enum IndexFormat {
  uint8,
  uint16,
  uint32,
}

enum PixelFormat {
  r8,
  rg8,
  rgb8,
  rgba8,
}

enum TextureUsage {
  static,
  dynamic,
  stream,
}

enum TextureFilter {
  nearest,
  linear,
}

enum TextureWrap {
  repeat,
  clamp,
  mirror,
}

enum BlendMode {
  none,
  alpha,
  additive,
  multiply,
}

enum CullMode {
  none,
  front,
  back,
  frontAndBack,
}

enum PrimitiveTopology {
  pointList,
  lineList,
  triangleList,
  triangleStrip,
}

enum GPURenderEventType {
  initialized,
  initializationFailed,
  glyphCreated,
  textureCreated,
  renderCompleted,
  renderFailed,
  settingsUpdated,
}

class GPURenderEvent {
  final GPURenderEventType type;
  final RenderBackend? backend;
  final String? glyphId;
  final String? character;
  final String? batchId;
  final int? cellCount;
  final Duration? renderTime;
  final String? error;

  GPURenderEvent({
    required this.type,
    this.backend,
    this.glyphId,
    this.character,
    this.batchId,
    this.cellCount,
    this.renderTime,
    this.error,
  });
}

class GPURenderStats {
  final int totalGlyphs;
  final int totalTextures;
  final int totalShaders;
  final int activeBatches;
  final int gpuMemoryUsed;
  final RenderBackend renderBackend;
  final bool isInitialized;
  final Duration averageRenderTime;
  final int droppedFrames;

  GPURenderStats({
    required this.totalGlyphs,
    required this.totalTextures,
    required this.totalShaders,
    required this.activeBatches,
    required this.gpuMemoryUsed,
    required this.renderBackend,
    required this.isInitialized,
    required this.averageRenderTime,
    required this.droppedFrames,
  });
}

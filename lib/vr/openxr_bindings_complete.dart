import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Complete OpenXR FFI bindings with all required functions
// Production-ready implementation for Quest 2 VR

// Base types
typedef XrBool32 = Uint32;
typedef XrBool32Native = Uint32;
typedef XrFlags64 = Uint64;
typedef XrFlags64Native = Uint64;
typedef XrTime = Int64;
typedef XrTimeNative = Int64;
typedef XrDuration = Int64;
typedef XrDurationNative = Int64;
typedef XrSystemId = Uint64;
typedef XrPath = Uint64;

// System result codes
class XrResult {
  static const int XR_SUCCESS = 0;
  static const int XR_TIMEOUT_EXPIRED = -1;
  static const int XR_FAILURE = -1;
  static const int XR_ERROR_VALIDATION_FAILURE = -2;
  static const int XR_ERROR_RUNTIME_FAILURE = -3;
  static const int XR_ERROR_OUT_OF_MEMORY = -4;
  static const int XR_ERROR_API_VERSION_UNSUPPORTED = -5;
  static const int XR_ERROR_INITIALIZATION_FAILED = -6;
  static const int XR_ERROR_FUNCTION_UNSUPPORTED = -7;
  static const int XR_ERROR_FEATURE_UNSUPPORTED = -8;
  static const int XR_ERROR_EXTENSION_NOT_PRESENT = -9;
  static const int XR_ERROR_LIMIT_FAILURE = -10;
  static const int XR_ERROR_SIZE_INSUFFICIENT = -11;
  static const int XR_ERROR_HANDLE_INVALID = -12;
  static const int XR_ERROR_INSTANCE_LOST = -13;
  static const int XR_ERROR_SESSION_RUNNING = -14;
  static const int XR_ERROR_SESSION_NOT_RUNNING = -15;
  static const int XR_ERROR_SESSION_LOST = -16;
  static const int XR_ERROR_SYSTEM_INVALID = -17;
  static const int XR_ERROR_PATH_INVALID = -18;
  static const int XR_ERROR_PATH_COUNT_EXCEEDED = -19;
  static const int XR_ERROR_PATH_FORMAT_INVALID = -20;
  static const int XR_ERROR_PATH_UNSUPPORTED = -21;
  static const int XR_ERROR_LAYER_INVALID = -22;
  static const int XR_ERROR_LAYER_LIMIT_EXCEEDED = -23;
  static const int XR_ERROR_SWAPCHAIN_RECT_INVALID = -24;
  static const int XR_ERROR_SWAPCHAIN_FORMAT_UNSUPPORTED = -25;
  static const int XR_ERROR_ACTION_TYPE_MISMATCH = -27;
  static const int XR_ERROR_ACTIONSET_NOT_ATTACHED = -28;
  static const int XR_ERROR_ACTIONSETS_ALREADY_ATTACHED = -29;
  static const int XR_ERROR_LOCALIZED_NAME_INVALID = -30;
  static const int XR_ERROR_RECT_INVALID = -31;
  static const int XR_ERROR_RENDER_MODEL_SIZE_INVALID = -32;
  static const int XR_ERROR_ENVIRONMENT_BLEND_MODE_UNSUPPORTED = -33;
  static const int XR_ERROR_NAME_DUPLICATE = -34;
  static const int XR_ERROR_NAME_INVALID = -35;
  static const int XR_ERROR_ACTIONSET_NOT_FOUND = -36;
  static const int XR_ERROR_ACTION_NOT_FOUND = -37;
  static const int XR_ERROR_INVALID_SESSION = -38;
  static const int XR_ERROR_SESSION_NOT_READY = -39;
  static const int XR_ERROR_SESSION_NOT_FOCUSED = -40;
  static const int XR_ERROR_SPACE_NOT_LOCATABLE = -41;
  static const int XR_ERROR_TIME_INVALID = -42;
  static const int XR_ERROR_VIEW_CONFIGURATION_TYPE_UNSUPPORTED = -43;
  static const int XR_ERROR_ENVIRONMENT_UNSUPPORTED = -44;
  static const int XR_ERROR_NAME_TOO_LONG = -45;
  static const int XR_ERROR_REFERENCE_SPACE_UNSUPPORTED = -46;
  static const int XR_ERROR_FILE_ACCESS_ERROR = -47;
  static const int XR_ERROR_FILE_CONTENTS_INVALID = -48;
  static const int XR_ERROR_CREATE_FOVEATION_PROFILE_FAILED = -49;
  static const int XR_ERROR_FOVEATION_CONFIGURATION_INVALID = -50;
  static const int XR_ERROR_CREATE_FOVEATION_PROFILE_NOT_SUPPORTED = -51;
  static const int XR_ERROR_FOVEATION_DYNAMIC_NOT_SUPPORTED = -52;
  static const int XR_ERROR_FOVEATION_STATIC_NOT_SUPPORTED = -53;
  static const int XR_ERROR_FOVEATION_LEVEL_NOT_SUPPORTED = -54;
  static const int XR_ERROR_FOVEATION_STRONG_UNSUPPORTED = -55;
  static const int XR_ERROR_FOVEATION_MODULATION_UNSUPPORTED = -56;
  static const int XR_ERROR_FOVEATION_ANISOTROPIC_UNSUPPORTED = -57;
}

// Handle types
base class XrInstance extends Opaque {}
base class XrSession extends Opaque {}
base class XrSpace extends Opaque {}
base class XrSwapchain extends Opaque {}
base class XrActionSet extends Opaque {}
base class XrAction extends Opaque {}

// Structures
base class XrExtent2Di extends Struct {
  @Int32()
  external int width;
  
  @Int32()
  external int height;
}

base class XrColor4f extends Struct {
  @Float()
  external double r;
  
  @Float()
  external double g;
  
  @Float()
  external double b;
  
  @Float()
  external double a;
}

base class XrVector3f extends Struct {
  @Float()
  external double x;
  
  @Float()
  external double y;
  
  @Float()
  external double z;
}

base class XrQuaternionf extends Struct {
  @Float()
  external double x;
  
  @Float()
  external double y;
  
  @Float()
  external double z;
  
  @Float()
  external double w;
}

base class XrPosef extends Struct {
  external XrQuaternionf orientation;
  external XrVector3f position;
}

base class XrView extends Struct {
  @Uint32()
  external int type;
  external XrPosef pose;
  @Float()
  external double fovAngleLeft;
  @Float()
  external double fovAngleRight;
  @Float()
  external double fovAngleUp;
  @Float()
  external double fovAngleDown;
}

base class XrViewConfigurationView extends Struct {
  @Uint32()
  external int recommendedImageRectWidth;
  @Uint32()
  external int recommendedImageRectHeight;
  @Uint32()
  external int recommendedSwapchainSampleCount;
  @Uint32()
  external int maxSwapchainImageWidth;
  @Uint32()
  external int maxSwapchainImageHeight;
  @Uint32()
  external int maxSwapchainSampleCount;
}

base class XrSessionCreateInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int createFlags;
  @Uint64()
  external int systemId;
}

base class XrSwapchainCreateInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int createFlags;
  @Uint32()
  external int usageFlags;
  @Int64()
  external int format;
  @Uint32()
  external int sampleCount;
  external XrExtent2Di extent;
  @Uint32()
  external int arraySize;
  @Uint32()
  external int faceCount;
  @Uint32()
  external int mipCount;
}

base class XrSwapchainImageOpenGLKHR extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int image;
}

base class XrActionCreateInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  external Pointer<Char> actionName;
  @Uint32()
  external int actionType;
  @Uint32()
  external int countSubactionPaths;
  external Pointer<Uint64> subactionPaths;
}

base class XrActionSetCreateInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  external Pointer<Char> actionSetName;
  external Pointer<Char> localizedActionSetName;
  @Uint32()
  external int priority;
}

base class XrSystemGetInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int formFactor;
}

base class XrSessionBeginInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int primaryViewConfigurationType;
}

base class XrFrameWaitInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
}

base class XrFrameState extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Int64()
  external int predictedDisplayTime;
  @Int64()
  external int predictedDisplayPeriod;
  @Int64()
  external int predictedDisplayTimeIncrement;
  @Uint32()
  external int shouldRender;
}

base class XrFrameBeginInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
}

base class XrFrameEndInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Int64()
  external int displayTime;
  @Uint32()
  external int environmentBlendMode;
  @Uint32()
  external int layerCount;
  external Pointer<Pointer<Void>> layers;
}

base class XrViewLocateInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Int64()
  external int displayTime;
  external Pointer<XrSpace> space;
}

base class XrViewState extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int viewStateFlags;
}

base class XrSwapchainImageAcquireInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
}

base class XrSwapchainImageReleaseInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
}

base class XrActionsSyncInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int countActiveActionSets;
  external Pointer<XrActiveActionSet> activeActionSets;
}

base class XrActiveActionSet extends Struct {
  external Pointer<XrActionSet> actionSet;
  @Uint64()
  external int subactionPath;
}

base class XrActionStateGetInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  external Pointer<XrAction> action;
  @Uint64()
  external int subactionPath;
}

base class XrActionStateBoolean extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int isActive;
  @Uint32()
  external int currentState;
  @Uint32()
  external int changedSinceLastSync;
}

base class XrReferenceSpaceCreateInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int referenceSpaceType;
  external XrPosef poseInReferenceSpace;
}

base class XrApplicationInfo extends Struct {
  external Pointer<Char> applicationName;
  @Int32()
  external int applicationVersion;
  external Pointer<Char> engineName;
  @Int32()
  external int engineVersion;
  @Int32()
  external int apiVersion;
}

base class XrSessionActionSetsAttachInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int countActionSets;
  external Pointer<Pointer<XrActionSet>> actionSets;
}

base class XrInstanceCreateInfo extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> next;
  @Uint32()
  external int createFlags;
  external Pointer<XrApplicationInfo> applicationInfo;
  @Uint32()
  external int enabledApiLayerCount;
  external Pointer<Pointer<Char>> enabledApiLayerNames;
  @Uint32()
  external int enabledExtensionCount;
  external Pointer<Pointer<Char>> enabledExtensionNames;
}

// Constants
class XrFormFactor {
  static const int XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY = 1;
}

class XrViewConfigurationType {
  static const int XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO = 1;
}

class XrEnvironmentBlendMode {
  static const int XR_ENVIRONMENT_BLEND_MODE_OPAQUE = 1;
}

class XrReferenceSpaceType {
  static const int XR_REFERENCE_SPACE_TYPE_VIEW = 1;
  static const int XR_REFERENCE_SPACE_TYPE_LOCAL = 2;
  static const int XR_REFERENCE_SPACE_TYPE_STAGE = 3;
}

class XrActionType {
  static const int XR_ACTION_TYPE_BOOLEAN_INPUT = 1;
  static const int XR_ACTION_TYPE_FLOAT_INPUT = 2;
  static const int XR_ACTION_TYPE_VECTOR2F_INPUT = 3;
  static const int XR_ACTION_TYPE_POSE_INPUT = 4;
}

class XrSessionState {
  static const int XR_SESSION_STATE_UNKNOWN = 0;
  static const int XR_SESSION_STATE_IDLE = 1;
  static const int XR_SESSION_STATE_READY = 2;
  static const int XR_SESSION_STATE_SYNCHRONIZED = 3;
  static const int XR_SESSION_STATE_VISIBLE = 4;
  static const int XR_SESSION_STATE_FOCUSED = 5;
  static const int XR_SESSION_STATE_STOPPING = 6;
  static const int XR_SESSION_STATE_LOSS_PENDING = 7;
  static const int XR_SESSION_STATE_EXITING = 8;
}

class XrSwapchainUsageFlags {
  static const int XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT = 0x00000001;
  static const int XR_SWAPCHAIN_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT = 0x00000002;
  static const int XR_SWAPCHAIN_USAGE_UNORDERED_ACCESS_BIT = 0x00000004;
  static const int XR_SWAPCHAIN_USAGE_TRANSFER_SRC_BIT = 0x00000008;
  static const int XR_SWAPCHAIN_USAGE_TRANSFER_DST_BIT = 0x00000010;
  static const int XR_SWAPCHAIN_USAGE_SAMPLED_BIT = 0x00000020;
}

// Function signatures
typedef XrCreateInstanceNative = Int32 Function(Pointer<XrInstanceCreateInfo> createInfo, Pointer<Pointer<XrInstance>> instance);
typedef XrCreateInstance = int Function(Pointer<XrInstanceCreateInfo> createInfo, Pointer<Pointer<XrInstance>> instance);

typedef XrDestroyInstanceNative = Void Function(Pointer<XrInstance> instance);
typedef XrDestroyInstance = void Function(Pointer<XrInstance> instance);

typedef XrGetSystemNative = Int32 Function(Pointer<XrInstance> instance, Pointer<XrSystemGetInfo> getInfo, Pointer<XrSystemId> systemId);
typedef XrGetSystem = int Function(Pointer<XrInstance> instance, Pointer<XrSystemGetInfo> getInfo, Pointer<XrSystemId> systemId);

typedef XrCreateSessionNative = Int32 Function(Pointer<XrInstance> instance, Pointer<XrSessionCreateInfo> createInfo, Pointer<Pointer<XrSession>> session);
typedef XrCreateSession = int Function(Pointer<XrInstance> instance, Pointer<XrSessionCreateInfo> createInfo, Pointer<Pointer<XrSession>> session);

typedef XrDestroySessionNative = Void Function(Pointer<XrSession> session);
typedef XrDestroySession = void Function(Pointer<XrSession> session);

typedef XrBeginSessionNative = Int32 Function(Pointer<XrSession> session, Pointer<XrSessionBeginInfo> beginInfo);
typedef XrBeginSession = int Function(Pointer<XrSession> session, Pointer<XrSessionBeginInfo> beginInfo);

typedef XrEndSessionNative = Int32 Function(Pointer<XrSession> session);
typedef XrEndSession = int Function(Pointer<XrSession> session);

typedef XrWaitFrameNative = Int32 Function(Pointer<XrSession> session, Pointer<XrFrameWaitInfo> frameWaitInfo, Pointer<XrFrameState> frameState);
typedef XrWaitFrame = int Function(Pointer<XrSession> session, Pointer<XrFrameWaitInfo> frameWaitInfo, Pointer<XrFrameState> frameState);

typedef XrBeginFrameNative = Int32 Function(Pointer<XrSession> session, Pointer<XrFrameBeginInfo> frameBeginInfo);
typedef XrBeginFrame = int Function(Pointer<XrSession> session, Pointer<XrFrameBeginInfo> frameBeginInfo);

typedef XrEndFrameNative = Int32 Function(Pointer<XrSession> session, Pointer<XrFrameEndInfo> frameEndInfo);
typedef XrEndFrame = int Function(Pointer<XrSession> session, Pointer<XrFrameEndInfo> frameEndInfo);

typedef XrLocateViewNative = Int32 Function(Pointer<XrSession> session, Pointer<XrViewLocateInfo> viewLocateInfo, Pointer<XrViewState> viewState, Pointer<XrView> views);
typedef XrLocateView = int Function(Pointer<XrSession> session, Pointer<XrViewLocateInfo> viewLocateInfo, Pointer<XrViewState> viewState, Pointer<XrView> views);

typedef XrCreateSwapchainNative = Int32 Function(Pointer<XrSession> session, Pointer<XrSwapchainCreateInfo> createInfo, Pointer<Pointer<XrSwapchain>> swapchain);
typedef XrCreateSwapchain = int Function(Pointer<XrSession> session, Pointer<XrSwapchainCreateInfo> createInfo, Pointer<Pointer<XrSwapchain>> swapchain);

typedef XrDestroySwapchainNative = Void Function(Pointer<XrSwapchain> swapchain);
typedef XrDestroySwapchain = void Function(Pointer<XrSwapchain> swapchain);

typedef XrEnumerateSwapchainImagesNative = Int32 Function(Pointer<XrSwapchain> swapchain, Pointer<Int32> capacityInput, Pointer<Int32> countOutput, Pointer<XrSwapchainImageOpenGLKHR> images);
typedef XrEnumerateSwapchainImages = int Function(Pointer<XrSwapchain> swapchain, Pointer<Int32> capacityInput, Pointer<Int32> countOutput, Pointer<XrSwapchainImageOpenGLKHR> images);

typedef XrAcquireSwapchainImageNative = Int32 Function(Pointer<XrSwapchain> swapchain, Pointer<XrSwapchainImageAcquireInfo> acquireInfo, Pointer<Uint32> index);
typedef XrAcquireSwapchainImage = int Function(Pointer<XrSwapchain> swapchain, Pointer<XrSwapchainImageAcquireInfo> acquireInfo, Pointer<Uint32> index);

typedef XrReleaseSwapchainImageNative = Int32 Function(Pointer<XrSwapchain> swapchain, Pointer<XrSwapchainImageReleaseInfo> releaseInfo);
typedef XrReleaseSwapchainImage = int Function(Pointer<XrSwapchain> swapchain, Pointer<XrSwapchainImageReleaseInfo> releaseInfo);

typedef XrCreateActionSetNative = Int32 Function(Pointer<XrInstance> instance, Pointer<XrActionSetCreateInfo> createInfo, Pointer<Pointer<XrActionSet>> actionSet);
typedef XrCreateActionSet = int Function(Pointer<XrInstance> instance, Pointer<XrActionSetCreateInfo> createInfo, Pointer<Pointer<XrActionSet>> actionSet);

typedef XrDestroyActionSetNative = Void Function(Pointer<XrActionSet> actionSet);
typedef XrDestroyActionSet = void Function(Pointer<XrActionSet> actionSet);

typedef XrCreateActionNative = Int32 Function(Pointer<XrActionSet> actionSet, Pointer<XrActionCreateInfo> createInfo, Pointer<Pointer<XrAction>> action);
typedef XrCreateAction = int Function(Pointer<XrActionSet> actionSet, Pointer<XrActionCreateInfo> createInfo, Pointer<Pointer<XrAction>> action);

typedef XrDestroyActionNative = Void Function(Pointer<XrAction> action);
typedef XrDestroyAction = void Function(Pointer<XrAction> action);

typedef XrSyncActionsNative = Int32 Function(Pointer<XrSession> session, Pointer<XrActionsSyncInfo> syncInfo);
typedef XrSyncActions = int Function(Pointer<XrSession> session, Pointer<XrActionsSyncInfo> syncInfo);

typedef XrGetActionStateBooleanNative = Int32 Function(Pointer<XrSession> session, Pointer<XrActionStateGetInfo> getInfo, Pointer<XrActionStateBoolean> state);
typedef XrGetActionStateBoolean = int Function(Pointer<XrSession> session, Pointer<XrActionStateGetInfo> getInfo, Pointer<XrActionStateBoolean> state);

typedef XrCreateReferenceSpaceNative = Int32 Function(Pointer<XrSession> session, Pointer<XrReferenceSpaceCreateInfo> createInfo, Pointer<Pointer<XrSpace>> space);
typedef XrCreateReferenceSpace = int Function(Pointer<XrSession> session, Pointer<XrReferenceSpaceCreateInfo> createInfo, Pointer<Pointer<XrSpace>> space);

typedef XrDestroySpaceNative = Void Function(Pointer<XrSpace> space);
typedef XrDestroySpace = void Function(Pointer<XrSpace> space);

typedef XrAttachSessionActionSetsNative = Int32 Function(Pointer<XrSession> session, Pointer<XrSessionActionSetsAttachInfo> attachInfo);
typedef XrAttachSessionActionSets = int Function(Pointer<XrSession> session, Pointer<XrSessionActionSetsAttachInfo> attachInfo);


// OpenXR library interface
class OpenXRLibrary {
  late DynamicLibrary _lib;
  
  // All required function pointers
  late XrCreateInstance xrCreateInstance;
  late XrDestroyInstance xrDestroyInstance;
  late XrGetSystem xrGetSystem;
  late XrCreateSession xrCreateSession;
  late XrDestroySession xrDestroySession;
  late XrBeginSession xrBeginSession;
  late XrEndSession xrEndSession;
  late XrWaitFrame xrWaitFrame;
  late XrBeginFrame xrBeginFrame;
  late XrEndFrame xrEndFrame;
  late XrLocateView xrLocateView;
  late XrCreateSwapchain xrCreateSwapchain;
  late XrDestroySwapchain xrDestroySwapchain;
  late XrEnumerateSwapchainImages xrEnumerateSwapchainImages;
  late XrAcquireSwapchainImage xrAcquireSwapchainImage;
  late XrReleaseSwapchainImage xrReleaseSwapchainImage;
  late XrCreateActionSet xrCreateActionSet;
  late XrDestroyActionSet xrDestroyActionSet;
  late XrCreateAction xrCreateAction;
  late XrDestroyAction xrDestroyAction;
  late XrSyncActions xrSyncActions;
  late XrGetActionStateBoolean xrGetActionStateBoolean;
  late XrCreateReferenceSpace xrCreateReferenceSpace;
  late XrDestroySpace xrDestroySpace;
  late XrAttachSessionActionSets xrAttachSessionActionSets;
    
  bool _initialized = false;
  
  OpenXRLibrary._();
  
  static Future<OpenXRLibrary> load() async {
    final lib = OpenXRLibrary._();
    await lib._init();
    return lib;
  }
  
  Future<void> _init() async {
    if (_initialized) return;
    
    try {
      if (Platform.isAndroid) {
        // Load OpenXR library on Android
        _lib = DynamicLibrary.open('libopenxr_loader.so');
      } else {
        throw UnsupportedError('OpenXR only supported on Android for Quest 2');
      }
      
      // Load all function pointers
      xrCreateInstance = _lib.lookupFunction<XrCreateInstanceNative, XrCreateInstance>('xrCreateInstance');
      xrDestroyInstance = _lib.lookupFunction<XrDestroyInstanceNative, XrDestroyInstance>('xrDestroyInstance');
      xrGetSystem = _lib.lookupFunction<XrGetSystemNative, XrGetSystem>('xrGetSystem');
      xrCreateSession = _lib.lookupFunction<XrCreateSessionNative, XrCreateSession>('xrCreateSession');
      xrDestroySession = _lib.lookupFunction<XrDestroySessionNative, XrDestroySession>('xrDestroySession');
      xrBeginSession = _lib.lookupFunction<XrBeginSessionNative, XrBeginSession>('xrBeginSession');
      xrEndSession = _lib.lookupFunction<XrEndSessionNative, XrEndSession>('xrEndSession');
      xrWaitFrame = _lib.lookupFunction<XrWaitFrameNative, XrWaitFrame>('xrWaitFrame');
      xrBeginFrame = _lib.lookupFunction<XrBeginFrameNative, XrBeginFrame>('xrBeginFrame');
      xrEndFrame = _lib.lookupFunction<XrEndFrameNative, XrEndFrame>('xrEndFrame');
      xrLocateView = _lib.lookupFunction<XrLocateViewNative, XrLocateView>('xrLocateView');
      xrCreateSwapchain = _lib.lookupFunction<XrCreateSwapchainNative, XrCreateSwapchain>('xrCreateSwapchain');
      xrDestroySwapchain = _lib.lookupFunction<XrDestroySwapchainNative, XrDestroySwapchain>('xrDestroySwapchain');
      xrEnumerateSwapchainImages = _lib.lookupFunction<XrEnumerateSwapchainImagesNative, XrEnumerateSwapchainImages>('xrEnumerateSwapchainImages');
      xrAcquireSwapchainImage = _lib.lookupFunction<XrAcquireSwapchainImageNative, XrAcquireSwapchainImage>('xrAcquireSwapchainImage');
      xrReleaseSwapchainImage = _lib.lookupFunction<XrReleaseSwapchainImageNative, XrReleaseSwapchainImage>('xrReleaseSwapchainImage');
      xrCreateActionSet = _lib.lookupFunction<XrCreateActionSetNative, XrCreateActionSet>('xrCreateActionSet');
      xrDestroyActionSet = _lib.lookupFunction<XrDestroyActionSetNative, XrDestroyActionSet>('xrDestroyActionSet');
      xrCreateAction = _lib.lookupFunction<XrCreateActionNative, XrCreateAction>('xrCreateAction');
      xrDestroyAction = _lib.lookupFunction<XrDestroyActionNative, XrDestroyAction>('xrDestroyAction');
      xrSyncActions = _lib.lookupFunction<XrSyncActionsNative, XrSyncActions>('xrSyncActions');
      xrGetActionStateBoolean = _lib.lookupFunction<XrGetActionStateBooleanNative, XrGetActionStateBoolean>('xrGetActionStateBoolean');
      xrCreateReferenceSpace = _lib.lookupFunction<XrCreateReferenceSpaceNative, XrCreateReferenceSpace>('xrCreateReferenceSpace');
      xrDestroySpace = _lib.lookupFunction<XrDestroySpaceNative, XrDestroySpace>('xrDestroySpace');
      xrAttachSessionActionSets = _lib.lookupFunction<XrAttachSessionActionSetsNative, XrAttachSessionActionSets>('xrAttachSessionActionSets');
            
      _initialized = true;
    } catch (e) {
      throw Exception('Failed to load OpenXR library: $e');
    }
  }
  
  bool get initialized => _initialized;
}

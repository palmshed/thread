#include "cuda_shim.h"

// Use Objective-C for Metal
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// Include CUDA shim header for error codes
#include "cuda_shim.h"

// Define missing CUDA error codes if not already defined
#ifndef cudaErrorInvalidDevicePointer
#define cudaErrorInvalidDevicePointer static_cast<cudaError_t>(17)
#endif

#ifndef cudaErrorInvalidMemcpyDirection
#define cudaErrorInvalidMemcpyDirection static_cast<cudaError_t>(21)
#endif

// Disable ARC for this file as we need manual memory management
#if __has_feature(objc_arc)
#error "This file must be compiled without ARC enabled"
#endif

#include <atomic>
#include <cstring> // for memcpy
#include <dispatch/dispatch.h>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>

// Manual memory management for Objective-C objects

// Forward declarations for Metal types
@protocol MTLCommandBuffer;
@protocol MTLSharedEvent;

// Structure to hold Metal stream information
struct MetalStream {
  id<MTLCommandQueue> queue;
  id<MTLCommandBuffer> lastCommandBuffer;
  std::mutex mutex;
  bool isNonBlocking;

  MetalStream(bool nonBlocking = false)
      : isNonBlocking(nonBlocking), lastCommandBuffer(nil) {}

  ~MetalStream() {
    if (lastCommandBuffer) {
      lastCommandBuffer = nil;
    }
  }

  // Prevent copying
  MetalStream(const MetalStream &) = delete;
  MetalStream &operator=(const MetalStream &) = delete;
};

// Structure to hold Metal event information
struct MetalEvent {
  id<MTLSharedEvent> event;
  uint64_t signalValue;
  bool isRecording;
  bool isCompleted;
  std::mutex mutex;

  MetalEvent()
      : event(nil), signalValue(1), isRecording(false), isCompleted(false) {}

  ~MetalEvent() {
    if (event) {
      event = nil;
    }
  }

  // Prevent copying
  MetalEvent(const MetalEvent &) = delete;
  MetalEvent &operator=(const MetalEvent &) = delete;
};

namespace {
class MetalShim {
private:
  dispatch_queue_t m_serialQueue;
  id<MTLDevice> m_device;
  id<MTLCommandQueue> m_commandQueue;
  id<MTLLibrary> m_defaultLibrary;
  std::unordered_map<void *, id<MTLBuffer>> m_buffers;
  std::unordered_map<std::string, id<MTLFunction>> m_functionCache;
  std::unordered_map<std::string, id<MTLComputePipelineState>> m_pipelineCache;
  std::mutex m_mutex;

  MetalShim()
      : m_serialQueue(dispatch_queue_create("com.thread.metalshim",
                                            DISPATCH_QUEUE_SERIAL)) {
    @autoreleasepool {
      // Create the Metal device
      m_device = MTLCreateSystemDefaultDevice();
      if (!m_device) {
        NSLog(@"Failed to create Metal device");
        return;
      }

      // Create command queue
      m_commandQueue = [m_device newCommandQueue];
      if (!m_commandQueue) {
        NSLog(@"Failed to create command queue");
        return;
      }
    }
  }

  ~MetalShim() {
    @autoreleasepool {
      // Release all buffers
      for (auto &pair : m_buffers) {
        [pair.second release];
      }
      m_buffers.clear();

      // Clear caches
      for (auto &pair : m_functionCache) {
        [pair.second release];
      }
      m_functionCache.clear();

      for (auto &pair : m_pipelineCache) {
        [pair.second release];
      }
      m_pipelineCache.clear();

      // Release Metal objects
      if (m_defaultLibrary) {
        [m_defaultLibrary release];
        m_defaultLibrary = nil;
      }

      if (m_commandQueue) {
        [m_commandQueue release];
        m_commandQueue = nil;
      }

      if (m_device) {
        [m_device release];
        m_device = nil;
      }
    }

    // Release the serial queue
    if (m_serialQueue) {
      dispatch_release(m_serialQueue);
      m_serialQueue = NULL;
    }
  }

public:
  static MetalShim &instance() {
    static MetalShim instance;
    return instance;
  }

  cudaError_t init() {
    if (!m_device || !m_commandQueue) {
      return cudaErrorInitializationError;
    }
    return cudaSuccess;
  }

  void shutdown() {
    @autoreleasepool {
      // Release all buffers
      for (auto &pair : m_buffers) {
        [pair.second release];
      }
      m_buffers.clear();

      // Clear caches
      for (auto &pair : m_functionCache) {
        [pair.second release];
      }
      m_functionCache.clear();

      for (auto &pair : m_pipelineCache) {
        [pair.second release];
      }
      m_pipelineCache.clear();

      // Release Metal objects
      if (m_defaultLibrary) {
        [m_defaultLibrary release];
        m_defaultLibrary = nil;
      }
      if (m_commandQueue) {
        [m_commandQueue release];
        m_commandQueue = nil;
      }
      if (m_device) {
        [m_device release];
        m_device = nil;
      }
      if (m_serialQueue) {
        dispatch_release(m_serialQueue);
        m_serialQueue = nullptr;
      }
    }
  }

  cudaError_t malloc(void **devPtr, size_t size) {
    if (!devPtr || size == 0)
      return cudaErrorInvalidValue;

    @autoreleasepool {
      if (!m_device)
        return cudaErrorInitializationError;

      // Create a new Metal buffer with shared storage mode
      id<MTLBuffer> buffer =
          [m_device newBufferWithLength:size
                                options:MTLResourceStorageModeShared];
      if (!buffer)
        return cudaErrorMemoryAllocation;

      // Store the buffer in our map and return the pointer
      std::lock_guard<std::mutex> lock(m_mutex);
      *devPtr = (__bridge void *)[buffer retain];
      m_buffers[*devPtr] = buffer;

      return cudaSuccess;
    }
  }

  cudaError_t free(void *devPtr) {
    if (!devPtr)
      return cudaSuccess;

    @autoreleasepool {
      std::lock_guard<std::mutex> lock(m_mutex);
      auto it = m_buffers.find(devPtr);
      if (it != m_buffers.end()) {
        // Release the buffer and remove from our map
        id<MTLBuffer> buffer = it->second;
        [buffer release];
        m_buffers.erase(it);

        return cudaSuccess;
      }
      return cudaErrorInvalidDevicePointer;
    }
  }

  cudaError_t memcpy(void *dst, const void *src, size_t count,
                      cudaMemcpyKind kind) {
    if (count == 0)
      return cudaSuccess;
    if (!dst || !src)
      return cudaErrorInvalidValue;

    @autoreleasepool {
      if (!m_commandQueue)
        return cudaErrorInitializationError;

      // For host-to-host memory copy, just use memcpy
      if (kind == cudaMemcpyHostToHost) {
        ::memcpy(dst, src, count);
        return cudaSuccess;
      }

      // For device-to-device or device-to-host, we need to use Metal
      id<MTLBuffer> srcBuffer = nil;
      id<MTLBuffer> dstBuffer = nil;

      // Get source buffer
      if (kind == cudaMemcpyHostToDevice || kind == cudaMemcpyDeviceToDevice) {
        std::lock_guard<std::mutex> lock(m_mutex);
        auto it = m_buffers.find((void *)src);
        if (it != m_buffers.end()) {
          srcBuffer = it->second;
        }
      }

      // Get destination buffer
      if (kind == cudaMemcpyDeviceToHost || kind == cudaMemcpyDeviceToDevice) {
        std::lock_guard<std::mutex> lock(m_mutex);
        auto it = m_buffers.find(dst);
        if (it != m_buffers.end()) {
          dstBuffer = it->second;
        }
      }

      // Handle different copy kinds
      switch (kind) {
      case cudaMemcpyHostToDevice:
        if (!dstBuffer)
          return cudaErrorInvalidDevicePointer;
        if ([dstBuffer length] < count)
          return cudaErrorInvalidValue;
        ::memcpy([dstBuffer contents], src, count);
        break;

      case cudaMemcpyDeviceToHost:
        if (!srcBuffer)
          return cudaErrorInvalidDevicePointer;
        if ([srcBuffer length] < count)
          return cudaErrorInvalidValue;
        ::memcpy(dst, [srcBuffer contents], count);
        break;

      case cudaMemcpyDeviceToDevice:
        if (!srcBuffer || !dstBuffer)
          return cudaErrorInvalidDevicePointer;
        if ([srcBuffer length] < count || [dstBuffer length] < count) {
          return cudaErrorInvalidValue;
        }
        ::memcpy([dstBuffer contents], [srcBuffer contents], count);
        break;

      default:
        return cudaErrorInvalidMemcpyDirection;
      }

      return cudaSuccess;
    }
  }

  cudaError_t memcpyAsyncWithEvent(void *dst, const void *src, size_t count,
                                   std::function<void()> memcpyFunc, MetalStream *stream) {
    // Create shared event for synchronization
    id<MTLSharedEvent> sharedEvent = [m_device newSharedEvent];
    if (!sharedEvent)
      return cudaErrorInitializationError;

    // Launch asynchronous memcpy and signal event
    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          memcpyFunc();
          [sharedEvent setSignaledValue:1];
        });

    // Create command buffer for the stream
    id<MTLCommandBuffer> commandBuffer = stream
                                              ? [stream->queue commandBuffer]
                                              : [m_commandQueue commandBuffer];
    if (!commandBuffer) {
      [sharedEvent release];
      return cudaErrorInitializationError;
    }

    // Encode wait for the event
    if (@available(macOS 10.14, *)) {
      [commandBuffer encodeWaitForEvent:sharedEvent value:1];
    } else {
      // MTLSharedEvent synchronization requires macOS 10.14+
      [sharedEvent release];
      return cudaErrorNotSupported;
    }

    [commandBuffer commit];

    if (stream) {
      std::lock_guard<std::mutex> streamLock(stream->mutex);
      stream->lastCommandBuffer = commandBuffer;
    }

    if (!stream || !stream->isNonBlocking) {
      [commandBuffer waitUntilCompleted];
    }

    [sharedEvent release];
    return cudaSuccess;
  }

  cudaError_t memcpyAsync(void *dst, const void *src, size_t count,
                           cudaMemcpyKind kind, MetalStream *stream) {
    if (count == 0)
      return cudaSuccess;

    @autoreleasepool {
      // For host-to-host memory copy, just use memcpy on a background thread
      if (kind == cudaMemcpyHostToHost) {
        dispatch_async(
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
              ::memcpy(dst, src, count);
            });
        return cudaSuccess;
      }

      // For device operations, we need to use Metal
      id<MTLBuffer> srcBuffer = nil;
      id<MTLBuffer> dstBuffer = nil;

      // Get source buffer
      if (kind == cudaMemcpyHostToDevice || kind == cudaMemcpyDeviceToDevice) {
        std::lock_guard<std::mutex> lock(m_mutex);
        auto it = m_buffers.find((void *)src);
        if (it != m_buffers.end()) {
          srcBuffer = it->second;
        }
      }

      // Get destination buffer
      if (kind == cudaMemcpyDeviceToHost || kind == cudaMemcpyDeviceToDevice) {
        std::lock_guard<std::mutex> lock(m_mutex);
        auto it = m_buffers.find(dst);
        if (it != m_buffers.end()) {
          dstBuffer = it->second;
        }
      }

      switch (kind) {
       case cudaMemcpyHostToDevice: {
         if (!dstBuffer)
           return cudaErrorInvalidDevicePointer;
         if ([dstBuffer length] < count)
           return cudaErrorInvalidValue;

         return memcpyAsyncWithEvent(dst, src, count, [=]() {
           ::memcpy([dstBuffer contents], src, count);
         }, stream);
       }

       case cudaMemcpyDeviceToHost: {
         if (!srcBuffer)
           return cudaErrorInvalidDevicePointer;
         if ([srcBuffer length] < count)
           return cudaErrorInvalidValue;

         return memcpyAsyncWithEvent(dst, src, count, [=]() {
           ::memcpy(dst, [srcBuffer contents], count);
         }, stream);
       }

      case cudaMemcpyDeviceToDevice: {
        if (!srcBuffer || !dstBuffer)
          return cudaErrorInvalidDevicePointer;
        if ([srcBuffer length] < count || [dstBuffer length] < count)
          return cudaErrorInvalidValue;

        id<MTLCommandBuffer> commandBuffer = stream
                                                  ? [stream->queue commandBuffer]
                                                  : [m_commandQueue commandBuffer];
        if (!commandBuffer)
          return cudaErrorInitializationError;

        // Create a blit command encoder
        id<MTLBlitCommandEncoder> blitEncoder =
            [commandBuffer blitCommandEncoder];
        if (!blitEncoder)
          return cudaErrorInitializationError;

        [blitEncoder copyFromBuffer:srcBuffer
                       sourceOffset:0
                           toBuffer:dstBuffer
                  destinationOffset:0
                               size:count];
        [blitEncoder endEncoding];

        // Commit the command buffer
        [commandBuffer commit];

        // Store the command buffer in the stream if provided
        if (stream) {
          std::lock_guard<std::mutex> streamLock(stream->mutex);
          stream->lastCommandBuffer = commandBuffer;
        }

        // If this is a blocking call, wait for the command buffer to complete
        if (!stream || !stream->isNonBlocking) {
          [commandBuffer waitUntilCompleted];
        }
        break;
      }

      default:
        return cudaErrorInvalidMemcpyDirection;
      }

      return cudaSuccess;
    }
  }

  cudaError_t memset(void *devPtr, int value, size_t count) {
    if (!devPtr || count == 0)
      return cudaSuccess;

    @autoreleasepool {
      id<MTLBuffer> buffer = (__bridge id<MTLBuffer>)devPtr;
      if (!buffer)
        return cudaErrorInvalidDevicePointer;

      if ([buffer length] < count)
        return cudaErrorInvalidValue;

      if ([buffer storageMode] != MTLStorageModeShared) {
        // For private or managed storage, we need to use a compute shader
        // For now, we'll just fail if the buffer isn't in shared mode
        return cudaErrorNotSupported;
      }

      // For shared storage, we can just use memset directly
      memset([buffer contents], value, count);
      return cudaSuccess;
    }
  }

  cudaError_t memsetAsync(void *devPtr, int value, size_t count,
                           MetalStream *stream) {
    if (!devPtr || count == 0)
      return cudaSuccess;

    @autoreleasepool {
      id<MTLBuffer> buffer = (__bridge id<MTLBuffer>)devPtr;
      if (!buffer)
        return cudaErrorInvalidDevicePointer;

      if ([buffer length] < count)
        return cudaErrorInvalidValue;

      if ([buffer storageMode] != MTLStorageModeShared) {
        // For private or managed storage, we need to use a compute shader
        // For now, we'll just fail if the buffer isn't in shared mode
        return cudaErrorNotSupported;
      }

      // For shared storage, we can just dispatch a block to do the memset
      void *contents = [buffer contents];
      dispatch_async(
          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            memset(contents, value, count);
          });

      return cudaSuccess;
    }
  }

  cudaError_t launchKernel(const void *func, unsigned int gridDimX,
                           unsigned int gridDimY, unsigned int gridDimZ,
                           unsigned int blockDimX, unsigned int blockDimY,
                           unsigned int blockDimZ, unsigned int sharedMem,
                           MetalStream *stream, void **args, void **extra) {
    // Not implemented yet
    return cudaErrorNotSupported;
  }

  cudaError_t deviceSynchronize() {
    @autoreleasepool {
      if (!m_commandQueue)
        return cudaErrorInitializationError;

      // Create a command buffer and wait for it to complete
      id<MTLCommandBuffer> commandBuffer = [m_commandQueue commandBuffer];
      if (!commandBuffer)
        return cudaErrorInitializationError;

      [commandBuffer commit];
      [commandBuffer waitUntilCompleted];

      return cudaSuccess;
    }
  }

  cudaError_t streamCreate(cudaStream_t *pStream) {
    if (!pStream)
      return cudaErrorInvalidValue;

    @autoreleasepool {
      if (!m_device)
        return cudaErrorInitializationError;

      MetalStream *stream = new MetalStream();
      stream->queue = [m_device newCommandQueue];
      if (!stream->queue) {
        delete stream;
        return cudaErrorInitializationError;
      }

      *pStream = stream;
      return cudaSuccess;
    }
  }

  cudaError_t streamDestroy(cudaStream_t stream) {
    if (!stream)
      return cudaErrorInvalidValue;

    MetalStream *metalStream = static_cast<MetalStream *>(stream);
    delete metalStream;
    return cudaSuccess;
  }

  cudaError_t streamSynchronize(MetalStream *stream) {
    if (!stream)
      return cudaErrorInvalidValue;

    @autoreleasepool {
      std::lock_guard<std::mutex> lock(stream->mutex);
      if (stream->lastCommandBuffer) {
        [stream->lastCommandBuffer waitUntilCompleted];
        stream->lastCommandBuffer = nil;
      }
      return cudaSuccess;
    }
  }

  cudaError_t eventRecord(MetalEvent *event, MetalStream *stream) {
    if (!event)
      return cudaErrorInvalidValue;

    std::lock_guard<std::mutex> lock(event->mutex);
    if (event->isRecording || event->isCompleted) {
      return cudaErrorInvalidValue;
    }

    @autoreleasepool {
      id<MTLCommandBuffer> commandBuffer = stream
                                               ? [stream->queue commandBuffer]
                                               : [m_commandQueue commandBuffer];

      if (!commandBuffer)
        return cudaErrorInitializationError;

      // Create a shared event
      event->event = [m_device newSharedEvent];
      if (!event->event)
        return cudaErrorInitializationError;

      // Encode a command to signal the event
      // For Metal 2.0+, we can use signalEvent:value:
      if (@available(macOS 10.14, *)) {
        id<MTLComputeCommandEncoder> computeEncoder =
            [commandBuffer computeCommandEncoder];
        if ([computeEncoder respondsToSelector:@selector(signalEvent:value:)]) {
          [(id)computeEncoder signalEvent:event->event
                                    value:event->signalValue];
        }
        [computeEncoder endEncoding];
      } else {
        // Fallback for older Metal versions - use a dummy compute shader
        id<MTLComputeCommandEncoder> computeEncoder =
            [commandBuffer computeCommandEncoder];
        [computeEncoder endEncoding];

        // Just signal the event directly since we can't use signalEvent:value:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [(id)event->event
            notifyListener:nil
                   atValue:event->signalValue
                     block:^(id<MTLSharedEvent> sharedEvent, uint64_t value){
                         // No-op
                     }];
#pragma clang diagnostic pop
      }

      // Commit the command buffer
      [commandBuffer commit];

      // Store the command buffer in the stream if provided
      if (stream) {
        std::lock_guard<std::mutex> streamLock(stream->mutex);
        stream->lastCommandBuffer = commandBuffer;
      }

      event->isRecording = true;
      return cudaSuccess;
    }
  }

  cudaError_t eventSynchronize(MetalEvent *event) {
    if (!event)
      return cudaErrorInvalidValue;

    std::lock_guard<std::mutex> lock(event->mutex);
    if (!event->isRecording || !event->event) {
      return cudaErrorInvalidValue;
    }

    // Wait for the event to be signaled
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [(id)event->event
        notifyListener:nil
               atValue:event->signalValue
                 block:^(id<MTLSharedEvent> sharedEvent, uint64_t value) {
                   std::lock_guard<std::mutex> lock(event->mutex);
                   event->isCompleted = true;
                   event->isRecording = false;
                 }];
#pragma clang diagnostic pop

    return cudaSuccess;
  }

  cudaError_t eventElapsedTime(float *ms, MetalEvent *start, MetalEvent *end) {
    if (!ms || !start || !end)
      return cudaErrorInvalidValue;

    std::lock_guard<std::mutex> lock1(start->mutex);
    std::lock_guard<std::mutex> lock2(end->mutex);

    if (!start->isCompleted || !end->isCompleted) {
      return cudaErrorNotReady;
    }

    // In a real implementation, we would use the GPU timestamp here
    // For now, we'll just return 0 as a placeholder
    *ms = 0.0f;
    return cudaSuccess;
  }
};
} // namespace

// C interface implementation
cudaError_t cudaShimInit() { return MetalShim::instance().init(); }

void cudaShimShutdown() { MetalShim::instance().shutdown(); }

cudaError_t cudaShimMalloc(void **devPtr, size_t size) {
  return MetalShim::instance().malloc(devPtr, size);
}

cudaError_t cudaShimFree(void *devPtr) {
  return MetalShim::instance().free(devPtr);
}

cudaError_t cudaShimMemcpy(void *dst, const void *src, size_t count,
                           cudaMemcpyKind kind) {
  return MetalShim::instance().memcpy(dst, src, count, kind);
}

cudaError_t cudaShimMemcpyAsync(void *dst, const void *src, size_t count,
                                cudaMemcpyKind kind, void *stream) {
  return MetalShim::instance().memcpyAsync(dst, src, count, kind,
                                           static_cast<MetalStream *>(stream));
}

cudaError_t cudaShimMemset(void *devPtr, int value, size_t count) {
  return MetalShim::instance().memset(devPtr, value, count);
}

cudaError_t cudaShimMemsetAsync(void *devPtr, int value, size_t count,
                                void *stream) {
  return MetalShim::instance().memsetAsync(devPtr, value, count,
                                           static_cast<MetalStream *>(stream));
}

cudaError_t cudaShimLaunchKernel(const void *func, unsigned int gridDimX,
                                 unsigned int gridDimY, unsigned int gridDimZ,
                                 unsigned int blockDimX, unsigned int blockDimY,
                                 unsigned int blockDimZ, unsigned int sharedMem,
                                 void *stream, void **args, void **extra) {
  return MetalShim::instance().launchKernel(
      func, gridDimX, gridDimY, gridDimZ, blockDimX, blockDimY, blockDimZ,
      sharedMem, static_cast<MetalStream *>(stream), args, extra);
}

cudaError_t cudaShimDeviceSynchronize() {
  return MetalShim::instance().deviceSynchronize();
}

cudaError_t cudaShimStreamSynchronize(void *stream) {
  return MetalShim::instance().streamSynchronize(
      static_cast<MetalStream *>(stream));
}

cudaError_t cudaShimEventRecord(void *event, void *stream) {
  return MetalShim::instance().eventRecord(static_cast<MetalEvent *>(event),
                                           static_cast<MetalStream *>(stream));
}

cudaError_t cudaShimEventSynchronize(void *event) {
  return MetalShim::instance().eventSynchronize(
      static_cast<MetalEvent *>(event));
}

cudaError_t cudaShimEventElapsedTime(float *ms, void *start, void *end) {
  return MetalShim::instance().eventElapsedTime(
      ms, static_cast<MetalEvent *>(start), static_cast<MetalEvent *>(end));
}

cudaError_t cudaShimStreamCreate(cudaStream_t *pStream) {
  return MetalShim::instance().streamCreate(pStream);
}

cudaError_t cudaShimStreamDestroy(cudaStream_t stream) {
  return MetalShim::instance().streamDestroy(stream);
}

// Function pointer initialization
cudaError_t (*cudaMallocPtr)(void **devPtr, size_t size) = nullptr;
cudaError_t (*cudaFreePtr)(void *devPtr) = nullptr;
cudaError_t (*cudaMemcpyPtr)(void *dst, const void *src, size_t count,
                             cudaMemcpyKind kind) = nullptr;
cudaError_t (*cudaMemcpyAsyncPtr)(void *dst, const void *src, size_t count,
                                  cudaMemcpyKind kind,
                                  cudaStream_t stream) = nullptr;
cudaError_t (*cudaMemsetPtr)(void *devPtr, int value, size_t count) = nullptr;
cudaError_t (*cudaMemsetAsyncPtr)(void *devPtr, int value, size_t count,
                                  cudaStream_t stream) = nullptr;
cudaError_t (*cudaLaunchKernelPtr)(const void *func, unsigned int gridDimX,
                                   unsigned int gridDimY, unsigned int gridDimZ,
                                   unsigned int blockDimX,
                                   unsigned int blockDimY,
                                   unsigned int blockDimZ,
                                   unsigned int sharedMem, cudaStream_t stream,
                                   void **args, void **extra) = nullptr;
cudaError_t (*cudaDeviceSynchronizePtr)() = nullptr;
cudaError_t (*cudaStreamCreatePtr)(cudaStream_t *pStream) = nullptr;
cudaError_t (*cudaStreamDestroyPtr)(cudaStream_t stream) = nullptr;
cudaError_t (*cudaStreamSynchronizePtr)(cudaStream_t stream) = nullptr;
cudaError_t (*cudaEventRecordPtr)(cudaEvent_t event,
                                  cudaStream_t stream) = nullptr;
cudaError_t (*cudaEventSynchronizePtr)(cudaEvent_t event) = nullptr;
cudaError_t (*cudaEventElapsedTimePtr)(float *ms, cudaEvent_t start,
                                       cudaEvent_t end) = nullptr;

// Initialize function pointers
extern "C" __attribute__((constructor)) void initCudaShim() {
  // Memory management
  cudaMallocPtr = [](void **devPtr, size_t size) -> cudaError_t {
    return MetalShim::instance().malloc(devPtr, size);
  };

  cudaFreePtr = [](void *devPtr) -> cudaError_t {
    return MetalShim::instance().free(devPtr);
  };

  // Memory operations
  cudaMemcpyPtr = [](void *dst, const void *src, size_t count,
                     cudaMemcpyKind kind) -> cudaError_t {
    return MetalShim::instance().memcpy(dst, src, count, kind);
  };

  cudaMemcpyAsyncPtr = [](void *dst, const void *src, size_t count,
                          cudaMemcpyKind kind,
                          cudaStream_t stream) -> cudaError_t {
    return MetalShim::instance().memcpyAsync(
        dst, src, count, kind, static_cast<MetalStream *>(stream));
  };

  cudaMemsetPtr = [](void *devPtr, int value, size_t count) -> cudaError_t {
    return MetalShim::instance().memset(devPtr, value, count);
  };

  cudaMemsetAsyncPtr = [](void *devPtr, int value, size_t count,
                          cudaStream_t stream) -> cudaError_t {
    return MetalShim::instance().memsetAsync(
        devPtr, value, count, static_cast<MetalStream *>(stream));
  };

  // Kernel launch
  cudaLaunchKernelPtr =
      [](const void *func, unsigned int gridDimX, unsigned int gridDimY,
         unsigned int gridDimZ, unsigned int blockDimX, unsigned int blockDimY,
         unsigned int blockDimZ, unsigned int sharedMem, cudaStream_t stream,
         void **args, void **extra) -> cudaError_t {
    return MetalShim::instance().launchKernel(
        func, gridDimX, gridDimY, gridDimZ, blockDimX, blockDimY, blockDimZ,
        sharedMem, static_cast<MetalStream *>(stream), args, extra);
  };

  // Synchronization
  cudaDeviceSynchronizePtr = []() -> cudaError_t {
    return MetalShim::instance().deviceSynchronize();
  };

  cudaStreamCreatePtr = [](cudaStream_t *pStream) -> cudaError_t {
    return MetalShim::instance().streamCreate(pStream);
  };

  cudaStreamDestroyPtr = [](cudaStream_t stream) -> cudaError_t {
    return MetalShim::instance().streamDestroy(stream);
  };

  cudaStreamSynchronizePtr = [](cudaStream_t stream) -> cudaError_t {
    return MetalShim::instance().streamSynchronize(
        static_cast<MetalStream *>(stream));
  };

  cudaStreamSynchronizePtr = [](cudaStream_t stream) -> cudaError_t {
    return MetalShim::instance().streamSynchronize(
        static_cast<MetalStream *>(stream));
  };

  // Event management
  cudaEventRecordPtr = [](cudaEvent_t event,
                          cudaStream_t stream) -> cudaError_t {
    return MetalShim::instance().eventRecord(
        static_cast<MetalEvent *>(event), static_cast<MetalStream *>(stream));
  };

  cudaEventSynchronizePtr = [](cudaEvent_t event) -> cudaError_t {
    return MetalShim::instance().eventSynchronize(
        static_cast<MetalEvent *>(event));
  };

  cudaEventElapsedTimePtr = [](float *ms, cudaEvent_t start,
                               cudaEvent_t end) -> cudaError_t {
    return MetalShim::instance().eventElapsedTime(
        ms, static_cast<MetalEvent *>(start), static_cast<MetalEvent *>(end));
  };
}

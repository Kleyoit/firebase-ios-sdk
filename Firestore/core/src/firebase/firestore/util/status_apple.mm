/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "Firestore/core/src/firebase/firestore/util/status.h"

#if defined(__APPLE__)

#include "Firestore/core/src/firebase/firestore/util/error_apple.h"
#include "Firestore/core/src/firebase/firestore/util/string_format.h"
#include "absl/memory/memory.h"

namespace firebase {
namespace firestore {
namespace util {

class UnderlyingNSError : public PlatformError {
 public:
  explicit UnderlyingNSError(NSError* error) : error_(error) {
  }

  static std::unique_ptr<UnderlyingNSError> Create(NSError* error) {
    return absl::make_unique<UnderlyingNSError>(error);
  }

  static NSError* Recover(
      const std::unique_ptr<PlatformError>& platform_error) {
    if (platform_error == nullptr) {
      return nil;
    }

    return static_cast<UnderlyingNSError*>(platform_error.get())->error();
  }

  std::unique_ptr<PlatformError> Copy() override {
    return absl::make_unique<UnderlyingNSError>(error_);
  }

  std::unique_ptr<PlatformError> WrapWith(FirestoreErrorCode code,
                                          std::string message) override {
    NSError* chain = MakeNSError(code, message, error_);
    return Create(chain);
  }

  NSError* error() const {
    return error_;
  }

 private:
  NSError* error_;
};

namespace {

/**
 * Converts a Firestore-generated NSError to the equivalent status.
 */
Status FromFirestoreNSError(NSError* error) {
  auto error_code = static_cast<int>(error.code);
  HARD_ASSERT(error_code >= FirestoreErrorCode::Cancelled &&
                  error_code <= FirestoreErrorCode::Unauthenticated,
              "Unknown error code");

  auto original = UnderlyingNSError::Create(error);

  return Status(static_cast<FirestoreErrorCode>(error_code),
                MakeString(error.localizedDescription))
                .WithPlatformError(std::move(original));
}

}  // namespace

Status Status::FromNSError(NSError* error) {
  if (!error) {
    return Status::OK();
  }

  if ([error.domain isEqual:FIRFirestoreErrorDomain]) {
    return FromFirestoreNSError(error);
  }

  auto original = UnderlyingNSError::Create(error);

  while (error) {
    if ([error.domain isEqualToString:NSPOSIXErrorDomain]) {
      return FromErrno(static_cast<int>(error.code),
                       MakeString(original->error().localizedDescription))
          .WithPlatformError(std::move(original));
    }

    error = error.userInfo[NSUnderlyingErrorKey];
  }

  return Status{FirestoreErrorCode::Unknown,
                StringFormat("Unknown error: %s", original->error())}
      .WithPlatformError(std::move(original));
}

NSError* Status::ToNSError() const {
  if (ok()) return nil;

  NSError* error = UnderlyingNSError::Recover(state_->platform_error);
  if (error) return error;

  return MakeNSError(code(), error_message());
}

}  // namespace util
}  // namespace firestore
}  // namespace firebase

#endif  // defined(__APPLE__)

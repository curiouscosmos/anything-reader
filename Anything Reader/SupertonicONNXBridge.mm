#import "SupertonicONNXBridge.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <array>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#define ORT_API_MANUAL_INIT 1
#include "/Users/damanmehta/Library/Developer/Xcode/DerivedData/Anything_Reader-fznozxeulprkpackkdujajfqhqfw/SourcePackages/artifacts/onnxruntime-swift-package-manager/onnxruntime/onnxruntime.xcframework/macos-arm64_x86_64/onnxruntime.framework/Versions/A/Headers/onnxruntime_cxx_api.h"

namespace {
constexpr NSInteger SupertonicErrorCode = 1;
static NSString *const SupertonicErrorDomain = @"SupertonicONNXBridgeErrorDomain";

struct SupertonicConfig {
    int sampleRate = 0;
    int baseChunkSize = 0;
    int chunkCompressFactor = 0;
    int latentDim = 0;
};

struct SupertonicStyleTensor {
    std::shared_ptr<std::vector<float>> storage;
    std::array<int64_t, 3> dims {};
};

struct SupertonicTextBatch {
    std::vector<std::vector<int64_t>> textIds;
    std::vector<std::vector<std::vector<float>>> textMask;
};

static NSError *SupertonicMakeError(NSString *message, NSInteger code = SupertonicErrorCode) {
    return [NSError errorWithDomain:SupertonicErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Supertonic synthesis failed."}];
}

static NSError *SupertonicErrorFromException(const std::exception &exception, NSInteger code = SupertonicErrorCode) {
    const char *what = exception.what();
    NSString *message = what != nullptr ? [NSString stringWithUTF8String:what] : @"Supertonic synthesis failed.";
    return SupertonicMakeError(message, code);
}

static std::string SupertonicPathString(NSURL *url) {
    if (url == nil || url.path == nil) {
        return {};
    }
    return std::string(url.path.UTF8String);
}

static NSData *SupertonicReadData(NSURL *url, NSError **error) {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    return data;
}

static id SupertonicJSONValue(NSURL *url, NSError **error) {
    NSData *data = SupertonicReadData(url, error);
    if (data == nil) {
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (object == nil) {
        return nil;
    }

    return object;
}

static SupertonicConfig SupertonicDecodeConfig(NSDictionary *dictionary) {
    SupertonicConfig config;
    NSDictionary *ae = dictionary[@"ae"];
    NSDictionary *ttl = dictionary[@"ttl"];
    config.sampleRate = [ae[@"sample_rate"] integerValue];
    config.baseChunkSize = [ae[@"base_chunk_size"] integerValue];
    config.chunkCompressFactor = [ttl[@"chunk_compress_factor"] integerValue];
    config.latentDim = [ttl[@"latent_dim"] integerValue];
    return config;
}

static SupertonicStyleTensor SupertonicDecodeStyleTensor(NSDictionary *dictionary) {
    SupertonicStyleTensor tensor;
    NSArray *dims = dictionary[@"dims"];
    NSArray *data = dictionary[@"data"];

    if (dims.count == 3) {
        tensor.dims = {
            [dims[0] longLongValue],
            [dims[1] longLongValue],
            [dims[2] longLongValue]
        };
    }

    tensor.storage = std::make_shared<std::vector<float>>();
    for (id planeValue in data) {
        for (id rowValue in planeValue) {
            for (id element in rowValue) {
                tensor.storage->push_back([element floatValue]);
            }
        }
    }
    return tensor;
}

static std::vector<int64_t> SupertonicLoadIndexer(NSURL *url, NSError **error) {
    id object = SupertonicJSONValue(url, error);
    if (![object isKindOfClass:[NSArray class]]) {
        if (error && *error == nil) {
            *error = SupertonicMakeError(@"Supertonic unicode indexer is invalid.");
        }
        return {};
    }

    std::vector<int64_t> indexer;
    indexer.reserve([object count]);
    for (NSNumber *number in (NSArray *)object) {
        indexer.push_back(number.longLongValue);
    }
    return indexer;
}

static NSString *SupertonicPreprocessText(NSString *input, NSString *lang) {
    NSMutableString *text = [[input decomposedStringWithCompatibilityMapping] mutableCopy];
    if (text == nil) {
        return @"";
    }

    NSDictionary<NSString *, NSString *> *replacements = @{
        @"–": @"-",
        @"‑": @"-",
        @"—": @"-",
        @"_": @" ",
        @"“": @"\"",
        @"”": @"\"",
        @"‘": @"'",
        @"’": @"'",
        @"´": @"'",
        @"`": @"'",
        @"[": @" ",
        @"]": @" ",
        @"|": @" ",
        @"/": @" ",
        @"#": @" ",
        @"→": @" ",
        @"←": @" "
    };

    [replacements enumerateKeysAndObjectsUsingBlock:^(NSString *oldValue, NSString *newValue, BOOL *stop) {
        [text replaceOccurrencesOfString:oldValue
                              withString:newValue
                                 options:0
                                   range:NSMakeRange(0, text.length)];
    }];

    for (NSString *symbol in @[ @"♥", @"☆", @"♡", @"©", @"\\" ]) {
        [text replaceOccurrencesOfString:symbol withString:@"" options:0 range:NSMakeRange(0, text.length)];
    }

    for (NSDictionary *pair in @[ @{@"old": @"@", @"new": @" at "},
                                  @{@"old": @"e.g.,", @"new": @"for example, "},
                                  @{@"old": @"i.e.,", @"new": @"that is, "} ]) {
        [text replaceOccurrencesOfString:pair[@"old"]
                              withString:pair[@"new"]
                                 options:0
                                   range:NSMakeRange(0, text.length)];
    }

    for (NSArray *pair in @[ @[ @" ,", @"," ],
                             @[ @" .", @"." ],
                             @[ @" !", @"!" ],
                             @[ @" ?", @"?" ],
                             @[ @" ;", @";" ],
                             @[ @" :", @":" ],
                             @[ @" '", @"'" ] ]) {
        [text replaceOccurrencesOfString:pair[0]
                              withString:pair[1]
                                 options:0
                                   range:NSMakeRange(0, text.length)];
    }

    while ([text containsString:@"\"\""]) {
        [text replaceOccurrencesOfString:@"\"\"" withString:@"\"" options:0 range:NSMakeRange(0, text.length)];
    }
    while ([text containsString:@"''"]) {
        [text replaceOccurrencesOfString:@"''" withString:@"'" options:0 range:NSMakeRange(0, text.length)];
    }
    while ([text containsString:@"``"]) {
        [text replaceOccurrencesOfString:@"``" withString:@"`" options:0 range:NSMakeRange(0, text.length)];
    }

    NSRegularExpression *whitespacePattern = [NSRegularExpression regularExpressionWithPattern:@"\\s+"
                                                                                      options:0
                                                                                        error:nil];
    text = [[whitespacePattern stringByReplacingMatchesInString:text
                                                        options:0
                                                          range:NSMakeRange(0, text.length)
                                                   withTemplate:@" "] mutableCopy];
    [text setString:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];

    if (text.length > 0) {
        unichar last = [text characterAtIndex:text.length - 1];
        NSCharacterSet *terminal = [NSCharacterSet characterSetWithCharactersInString:@".!?;:,'\"”’)】〉》»"];
        if (![terminal characterIsMember:last]) {
            [text appendString:@"."];
        }
    }

    if (lang.length > 0) {
        return [NSString stringWithFormat:@"<%@>%@</%@>", lang, text, lang];
    }

    return text;
}

static std::vector<std::string> SupertonicChunkText(NSString *text, NSUInteger maxLen) {
    NSArray<NSString *> *chunks = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (chunks.count == 0) {
        chunks = @[text];
    }

    std::vector<std::string> result;
    std::string current;
    for (NSString *chunk in chunks) {
        NSString *trimmed = [chunk stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }

        std::string candidate = current.empty()
            ? std::string(trimmed.UTF8String)
            : current + " " + std::string(trimmed.UTF8String);

        if (current.empty()) {
            current = candidate;
        } else if (candidate.size() <= maxLen) {
            current = candidate;
        } else {
            result.push_back(current);
            current = std::string(trimmed.UTF8String);
        }
    }

    if (!current.empty()) {
        result.push_back(current);
    }

    if (result.empty()) {
        result.push_back(std::string(text.UTF8String));
    }

    return result;
}

static std::vector<std::vector<float>> SupertonicLengthToMask(const std::vector<int> &lengths, int maxLen) {
    std::vector<std::vector<float>> masks;
    masks.reserve(lengths.size());
    for (int length : lengths) {
        std::vector<float> row(static_cast<size_t>(maxLen), 0.0f);
        for (int index = 0; index < std::min(length, maxLen); ++index) {
            row[static_cast<size_t>(index)] = 1.0f;
        }
        masks.push_back(std::move(row));
    }
    return masks;
}

static std::vector<float> SupertonicFlattenTensor(const std::vector<std::vector<std::vector<float>>> &tensor) {
    std::vector<float> flat;
    size_t totalSize = 0;
    for (const auto &batch : tensor) {
        for (const auto &plane : batch) {
            totalSize += plane.size();
        }
    }

    flat.reserve(totalSize);
    for (const auto &batch : tensor) {
        for (const auto &plane : batch) {
            flat.insert(flat.end(), plane.begin(), plane.end());
        }
    }
    return flat;
}

static std::pair<std::vector<std::vector<std::vector<float>>>, std::vector<std::vector<std::vector<float>>>> SupertonicSampleNoisyLatent(
    const std::vector<float> &duration,
    int sampleRate,
    int baseChunkSize,
    int chunkCompress,
    int latentDim) {
    const size_t batchSize = duration.size();
    const float maxDuration = duration.empty() ? 0.0f : *std::max_element(duration.begin(), duration.end());
    const int wavLenMax = static_cast<int>(maxDuration * static_cast<float>(sampleRate));

    std::vector<int> wavLengths;
    wavLengths.reserve(batchSize);
    for (float seconds : duration) {
        wavLengths.push_back(static_cast<int>(seconds * static_cast<float>(sampleRate)));
    }

    const int chunkSize = baseChunkSize * chunkCompress;
    const int latentLen = (wavLenMax + chunkSize - 1) / chunkSize;
    const int latentDimValue = latentDim * chunkCompress;

    std::vector<std::vector<std::vector<float>>> noisyLatent;
    noisyLatent.reserve(batchSize);

    for (size_t batch = 0; batch < batchSize; ++batch) {
        std::vector<std::vector<float>> depth;
        depth.reserve(static_cast<size_t>(latentDimValue));
        for (int d = 0; d < latentDimValue; ++d) {
            std::vector<float> row;
            row.reserve(static_cast<size_t>(latentLen));
            for (int t = 0; t < latentLen; ++t) {
                const float u1 = static_cast<float>(arc4random_uniform(10000) + 1) / 10000.0f;
                const float u2 = static_cast<float>(arc4random_uniform(10000)) / 10000.0f;
                row.push_back(std::sqrt(-2.0f * std::log(u1)) * std::cos(2.0f * static_cast<float>(M_PI) * u2));
            }
            depth.push_back(std::move(row));
        }
        noisyLatent.push_back(std::move(depth));
    }

    std::vector<int> latentLengths;
    latentLengths.reserve(wavLengths.size());
    for (int wavLength : wavLengths) {
        latentLengths.push_back((wavLength + chunkSize - 1) / chunkSize);
    }

    std::vector<std::vector<std::vector<float>>> latentMask;
    latentMask.reserve(batchSize);
    auto masks = SupertonicLengthToMask(latentLengths, latentLen);
    for (const auto &maskRow : masks) {
        latentMask.push_back({maskRow});
    }

    for (size_t batch = 0; batch < batchSize; ++batch) {
        for (int depth = 0; depth < latentDimValue; ++depth) {
            for (int time = 0; time < latentLen; ++time) {
                noisyLatent[batch][depth][time] *= latentMask[batch][0][time];
            }
        }
    }

    return {noisyLatent, latentMask};
}

class SupertonicUnicodeProcessor {
public:
    explicit SupertonicUnicodeProcessor(std::vector<int64_t> indexer)
        : indexer_(std::move(indexer)) {}

    SupertonicTextBatch call(NSString *text, NSString *lang) const {
        NSString *processed = SupertonicPreprocessText(text, lang);
        NSArray<NSString *> *lines = [processed componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray<NSString *> *chunks = [NSMutableArray array];
        for (NSString *line in lines.count == 0 ? @[processed] : lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [chunks addObject:trimmed];
            }
        }
        if (chunks.count == 0) {
            [chunks addObject:processed];
        }

        SupertonicTextBatch batch;
        std::vector<int> lengths;
        lengths.reserve(chunks.count);
        for (NSString *chunk in chunks) {
            lengths.push_back(static_cast<int>(chunk.length));
        }

        const int maxLen = lengths.empty() ? 0 : *std::max_element(lengths.begin(), lengths.end());
        batch.textIds.reserve(chunks.count);

        for (NSString *chunk in chunks) {
            std::vector<int64_t> row(static_cast<size_t>(maxLen), 0);
            for (NSUInteger index = 0; index < chunk.length; ++index) {
                unichar scalar = [chunk characterAtIndex:index];
                const int value = static_cast<int>(scalar);
                row[static_cast<size_t>(index)] = value < static_cast<int>(indexer_.size()) ? indexer_[static_cast<size_t>(value)] : -1;
            }
            batch.textIds.push_back(std::move(row));
        }

        batch.textMask.reserve(lengths.size());
        for (int length : lengths) {
            std::vector<float> row(static_cast<size_t>(maxLen), 0.0f);
            for (int index = 0; index < std::min(length, maxLen); ++index) {
                row[static_cast<size_t>(index)] = 1.0f;
            }
            batch.textMask.push_back({std::move(row)});
        }

        return batch;
    }

private:
    std::vector<int64_t> indexer_;
};

class SupertonicStyle {
public:
    SupertonicStyle(SupertonicStyleTensor ttlTensor, SupertonicStyleTensor dpTensor) {
        ttlStorage_ = std::move(ttlTensor.storage);
        dpStorage_ = std::move(dpTensor.storage);

        const std::vector<int64_t> ttlShape = { ttlTensor.dims[0], ttlTensor.dims[1], ttlTensor.dims[2] };
        const std::vector<int64_t> dpShape = { dpTensor.dims[0], dpTensor.dims[1], dpTensor.dims[2] };
        auto memoryInfo = Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeCPU);

        ttl_.emplace(Ort::Value::CreateTensor<float>(
            memoryInfo,
            ttlStorage_->data(),
            ttlStorage_->size(),
            ttlShape.data(),
            ttlShape.size()
        ));

        dp_.emplace(Ort::Value::CreateTensor<float>(
            memoryInfo,
            dpStorage_->data(),
            dpStorage_->size(),
            dpShape.data(),
            dpShape.size()
        ));
    }

    const Ort::Value &ttl() const { return *ttl_; }
    const Ort::Value &dp() const { return *dp_; }

private:
    std::shared_ptr<std::vector<float>> ttlStorage_;
    std::shared_ptr<std::vector<float>> dpStorage_;
    std::optional<Ort::Value> ttl_;
    std::optional<Ort::Value> dp_;
};

class SupertonicTextToSpeech {
public:
    SupertonicTextToSpeech(SupertonicConfig config, std::vector<int64_t> indexer, const std::string &modelRootPath)
        : config_(config), textProcessor_(std::move(indexer)) {
        env_.emplace(ORT_LOGGING_LEVEL_WARNING, "supertonic");

        Ort::SessionOptions sessionOptions;
        sessionOptions.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        sessionOptions.SetIntraOpNumThreads(2);
        sessionOptions.SetInterOpNumThreads(1);
        sessionOptions.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
        const std::string onnxRoot = modelRootPath + "/onnx";

        dpOrt_.emplace(*env_, (onnxRoot + "/duration_predictor.onnx").c_str(), sessionOptions);
        textEncOrt_.emplace(*env_, (onnxRoot + "/text_encoder.onnx").c_str(), sessionOptions);
        vectorEstOrt_.emplace(*env_, (onnxRoot + "/vector_estimator.onnx").c_str(), sessionOptions);
        vocoderOrt_.emplace(*env_, (onnxRoot + "/vocoder.onnx").c_str(), sessionOptions);
    }

    std::vector<float> synthesize(NSString *text, NSString *lang, const SupertonicStyle &style) const {
        const int maxLen = (lang != nil && ([lang isEqualToString:@"ko"] || [lang isEqualToString:@"ja"])) ? 120 : 300;
        std::vector<std::string> chunks = SupertonicChunkText(text, static_cast<NSUInteger>(maxLen));
        std::vector<float> wavCat;
        float durCat = 0.0f;

        for (size_t index = 0; index < chunks.size(); ++index) {
            const std::string &chunk = chunks[index];
            auto result = infer({chunk}, {lang.UTF8String ?: ""}, style, 8, 1.05f);
            const float duration = result.second[0];
            const size_t wavLen = std::min(static_cast<size_t>(duration * static_cast<float>(config_.sampleRate)), result.first.size());
            std::vector<float> wavChunk(result.first.begin(), result.first.begin() + wavLen);

            if (index == 0) {
                wavCat = std::move(wavChunk);
                durCat = duration;
            } else {
                const size_t silenceLen = static_cast<size_t>(0.3f * static_cast<float>(config_.sampleRate));
                wavCat.insert(wavCat.end(), silenceLen, 0.0f);
                wavCat.insert(wavCat.end(), wavChunk.begin(), wavChunk.end());
                durCat += 0.3f + duration;
            }
        }

        (void)durCat;
        return wavCat;
    }

    int sampleRate() const { return config_.sampleRate; }

private:
    std::pair<std::vector<float>, std::vector<float>> infer(
        const std::vector<std::string> &textList,
        const std::vector<std::string> &langList,
        const SupertonicStyle &style,
        int totalStep,
        float speed) const {

        const size_t batchSize = textList.size();
        const SupertonicTextBatch batch = textProcessor_.call([NSString stringWithUTF8String:textList.front().c_str()],
                                                              [NSString stringWithUTF8String:langList.front().c_str()]);

        std::vector<int64_t> textIdsFlat;
        for (const auto &row : batch.textIds) {
            textIdsFlat.insert(textIdsFlat.end(), row.begin(), row.end());
        }

        std::vector<int64_t> textShape = {
            static_cast<int64_t>(batchSize),
            static_cast<int64_t>(batch.textIds.empty() ? 0 : batch.textIds[0].size())
        };
        auto memoryInfo = Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeCPU);
        Ort::Value textIdsValue = Ort::Value::CreateTensor<int64_t>(
            memoryInfo,
            textIdsFlat.data(),
            textIdsFlat.size(),
            textShape.data(),
            textShape.size()
        );

        std::vector<float> textMaskFlat;
        for (const auto &row : batch.textMask) {
            for (const auto &plane : row) {
                textMaskFlat.insert(textMaskFlat.end(), plane.begin(), plane.end());
            }
        }

        std::vector<int64_t> textMaskShape = {
            static_cast<int64_t>(batchSize),
            1,
            static_cast<int64_t>(batch.textMask.empty() ? 0 : batch.textMask[0][0].size())
        };
        Ort::Value textMaskValue = Ort::Value::CreateTensor<float>(
            memoryInfo,
            textMaskFlat.data(),
            textMaskFlat.size(),
            textMaskShape.data(),
            textMaskShape.size()
        );

        const char *dpInputNames[] = { "text_ids", "style_dp", "text_mask" };
        const char *dpOutputNames[] = { "duration" };
        const OrtValue *dpInputs[] = {
            static_cast<const OrtValue*>(textIdsValue),
            static_cast<const OrtValue*>(style.dp()),
            static_cast<const OrtValue*>(textMaskValue)
        };
        OrtValue *dpOutputValues[] = { nullptr };
        Ort::ThrowOnError(Ort::GetApi().Run(
            static_cast<OrtSession*>(*dpOrt_),
            nullptr,
            dpInputNames,
            dpInputs,
            3,
            dpOutputNames,
            1,
            dpOutputValues
        ));
        Ort::Value dpOutput{dpOutputValues[0]};
        std::vector<Ort::Value> dpOutputs;
        dpOutputs.push_back(std::move(dpOutput));

        const auto durationInfo = dpOutputs[0].GetTensorTypeAndShapeInfo();
        const size_t durationCount = durationInfo.GetElementCount();
        const float *durationData = dpOutputs[0].GetTensorData<float>();
        std::vector<float> duration(durationData, durationData + durationCount);
        for (float &value : duration) {
            value /= speed;
        }

        const char *teInputNames[] = { "text_ids", "style_ttl", "text_mask" };
        const char *teOutputNames[] = { "text_emb" };
        const OrtValue *teInputs[] = {
            static_cast<const OrtValue*>(textIdsValue),
            static_cast<const OrtValue*>(style.ttl()),
            static_cast<const OrtValue*>(textMaskValue)
        };
        OrtValue *teOutputValues[] = { nullptr };
        Ort::ThrowOnError(Ort::GetApi().Run(
            static_cast<OrtSession*>(*textEncOrt_),
            nullptr,
            teInputNames,
            teInputs,
            3,
            teOutputNames,
            1,
            teOutputValues
        ));
        Ort::Value textEmbOutput{teOutputValues[0]};
        const Ort::Value &textEmbValue = textEmbOutput;

        auto latentPair = SupertonicSampleNoisyLatent(duration, config_.sampleRate, config_.baseChunkSize, config_.chunkCompressFactor, config_.latentDim);
        std::vector<std::vector<std::vector<float>>> xt = latentPair.first;
        std::vector<std::vector<std::vector<float>>> latentMask = latentPair.second;
        std::vector<float> xtFlat = SupertonicFlattenTensor(xt);
        std::vector<float> latentMaskFlat = SupertonicFlattenTensor(latentMask);
        const size_t latentDimValue = xt.empty() ? 0 : xt[0].size();
        const size_t latentLen = xt.empty() || xt[0].empty() ? 0 : xt[0][0].size();

        std::vector<float> totalStepArray(batchSize, static_cast<float>(totalStep));
        std::vector<int64_t> totalStepShape = { static_cast<int64_t>(batchSize) };
        Ort::Value totalStepValue = Ort::Value::CreateTensor<float>(
            memoryInfo,
            totalStepArray.data(),
            totalStepArray.size(),
            totalStepShape.data(),
            totalStepShape.size()
        );
        std::vector<int64_t> xtShape = {
            static_cast<int64_t>(batchSize),
            static_cast<int64_t>(latentDimValue),
            static_cast<int64_t>(latentLen)
        };
        std::vector<int64_t> latentMaskShape = {
            static_cast<int64_t>(batchSize),
            1,
            static_cast<int64_t>(latentLen)
        };
        Ort::Value latentMaskValue = Ort::Value::CreateTensor<float>(
            memoryInfo,
            latentMaskFlat.data(),
            latentMaskFlat.size(),
            latentMaskShape.data(),
            latentMaskShape.size()
        );
        std::vector<int64_t> currentStepShape = { static_cast<int64_t>(batchSize) };

        for (int step = 0; step < totalStep; ++step) {
            std::vector<float> currentStepArray(batchSize, static_cast<float>(step));
            Ort::Value currentStepValue = Ort::Value::CreateTensor<float>(
                memoryInfo,
                currentStepArray.data(),
                currentStepArray.size(),
                currentStepShape.data(),
                currentStepShape.size()
            );

            Ort::Value xtValue = Ort::Value::CreateTensor<float>(
                memoryInfo,
                xtFlat.data(),
                xtFlat.size(),
                xtShape.data(),
                xtShape.size()
            );

            const char *veInputNames[] = {
                "noisy_latent",
                "text_emb",
                "style_ttl",
                "latent_mask",
                "text_mask",
                "current_step",
                "total_step"
            };
            const char *veOutputNames[] = { "denoised_latent" };
            const OrtValue *veInputs[] = {
                static_cast<const OrtValue*>(xtValue),
                static_cast<const OrtValue*>(textEmbValue),
                static_cast<const OrtValue*>(style.ttl()),
                static_cast<const OrtValue*>(latentMaskValue),
                static_cast<const OrtValue*>(textMaskValue),
                static_cast<const OrtValue*>(currentStepValue),
                static_cast<const OrtValue*>(totalStepValue)
            };
            OrtValue *veOutputValues[] = { nullptr };
            Ort::ThrowOnError(Ort::GetApi().Run(
                static_cast<OrtSession*>(*vectorEstOrt_),
                nullptr,
                veInputNames,
                veInputs,
                7,
                veOutputNames,
                1,
                veOutputValues
            ));
            Ort::Value veOutput{veOutputValues[0]};
            const auto denoisedInfo = veOutput.GetTensorTypeAndShapeInfo();
            const size_t denoisedCount = denoisedInfo.GetElementCount();
            const float *denoisedData = veOutput.GetTensorData<float>();
            xtFlat.assign(denoisedData, denoisedData + denoisedCount);
        }

        Ort::Value finalXtValue = Ort::Value::CreateTensor<float>(
            memoryInfo,
            xtFlat.data(),
            xtFlat.size(),
            xtShape.data(),
            xtShape.size()
        );

        const char *vocInputNames[] = { "latent" };
        const OrtValue *vocInputs[] = { static_cast<const OrtValue*>(finalXtValue) };
        const char *vocOutputNames[] = { "wav_tts" };
        OrtValue *vocOutputValues[] = { nullptr };
        Ort::ThrowOnError(Ort::GetApi().Run(
            static_cast<OrtSession*>(*vocoderOrt_),
            nullptr,
            vocInputNames,
            vocInputs,
            1,
            vocOutputNames,
            1,
            vocOutputValues
        ));
        Ort::Value vocOutput{vocOutputValues[0]};
        const auto wavInfo = vocOutput.GetTensorTypeAndShapeInfo();
        const size_t wavCount = wavInfo.GetElementCount();
        const float *wavData = vocOutput.GetTensorData<float>();
        std::vector<float> wav(wavData, wavData + wavCount);
        return { wav, duration };
    }

    std::optional<Ort::Session> dpOrt_;
    std::optional<Ort::Session> textEncOrt_;
    std::optional<Ort::Session> vectorEstOrt_;
    std::optional<Ort::Session> vocoderOrt_;
    std::optional<Ort::Env> env_;
    SupertonicConfig config_;
    SupertonicUnicodeProcessor textProcessor_;
};

static std::shared_ptr<SupertonicTextToSpeech> SupertonicLoadEngine(NSURL *rootURL, NSError **error) {
    NSArray<NSURL *> *configCandidates = @[
        [rootURL URLByAppendingPathComponent:@"config.json"],
        [rootURL URLByAppendingPathComponent:@"tts.json"],
        [[rootURL URLByAppendingPathComponent:@"onnx"] URLByAppendingPathComponent:@"tts.json"]
    ];

    NSDictionary *configDictionary = nil;
    for (NSURL *candidate in configCandidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
            id json = SupertonicJSONValue(candidate, error);
            if (![json isKindOfClass:[NSDictionary class]]) {
                return nil;
            }
            configDictionary = (NSDictionary *)json;
            break;
        }
    }

    if (configDictionary == nil) {
        if (error && *error == nil) {
            *error = SupertonicMakeError(@"Supertonic config file was not found.");
        }
        return nil;
    }

    NSURL *indexerURL = [[rootURL URLByAppendingPathComponent:@"onnx"] URLByAppendingPathComponent:@"unicode_indexer.json"];
    NSError *indexerError = nil;
    std::vector<int64_t> indexer = SupertonicLoadIndexer(indexerURL, &indexerError);
    if (indexer.empty() && indexerError != nil) {
        if (error) {
            *error = indexerError;
        }
        return nil;
    }

    SupertonicConfig config = SupertonicDecodeConfig(configDictionary);
    return std::make_shared<SupertonicTextToSpeech>(config, std::move(indexer), SupertonicPathString(rootURL));
}

static std::shared_ptr<SupertonicStyle> SupertonicLoadStyle(NSURL *rootURL, NSString *voiceName, NSError **error) {
    NSURL *styleURL = [[rootURL URLByAppendingPathComponent:@"voice_styles"] URLByAppendingPathComponent:[voiceName stringByAppendingPathExtension:@"json"]];
    id json = SupertonicJSONValue(styleURL, error);
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error && *error == nil) {
            *error = SupertonicMakeError(@"Supertonic voice style file was not found.");
        }
        return nil;
    }

    NSDictionary *dictionary = (NSDictionary *)json;
    NSDictionary *ttlDictionary = dictionary[@"style_ttl"];
    NSDictionary *dpDictionary = dictionary[@"style_dp"];
    SupertonicStyleTensor ttlTensor = SupertonicDecodeStyleTensor(ttlDictionary);
    SupertonicStyleTensor dpTensor = SupertonicDecodeStyleTensor(dpDictionary);
    return std::make_shared<SupertonicStyle>(std::move(ttlTensor), std::move(dpTensor));
}

static NSURL *SupertonicWriteWaveFile(const std::vector<float> &samples, double sampleRate, NSError **error) {
    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"wav"]]];

    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                            sampleRate:sampleRate
                                                              channels:1
                                                           interleaved:NO];
    if (format == nil) {
        if (error) {
            *error = SupertonicMakeError(@"Unable to create the audio format.");
        }
        return nil;
    }

    AVAudioFrameCount frameCount = static_cast<AVAudioFrameCount>(samples.size());
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frameCount];
    if (buffer == nil) {
        if (error) {
            *error = SupertonicMakeError(@"Unable to allocate the audio buffer.");
        }
        return nil;
    }

    buffer.frameLength = frameCount;
    if (buffer.floatChannelData != nullptr && buffer.floatChannelData[0] != nullptr) {
        std::memcpy(buffer.floatChannelData[0], samples.data(), samples.size() * sizeof(float));
    }

    NSError *fileError = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForWriting:tempURL
                                                   settings:format.settings
                                                      error:&fileError];
    if (file == nil) {
        if (error) {
            *error = fileError ?: SupertonicMakeError(@"Unable to open the WAV file for writing.");
        }
        return nil;
    }

    [file writeFromBuffer:buffer error:&fileError];
    if (fileError != nil) {
        if (error) {
            *error = fileError;
        }
        return nil;
    }

    return tempURL;
}
} // namespace

__attribute__((constructor))
static void SupertonicInitializeOnnxRuntimeBridge(void) {
    Ort::InitApi(OrtGetApiBase()->GetApi(23));
}

@interface SupertonicONNXBridge () {
    std::unordered_map<std::string, std::shared_ptr<SupertonicTextToSpeech>> _engineCache;
    std::unordered_map<std::string, std::shared_ptr<SupertonicStyle>> _styleCache;
}
@end

@implementation SupertonicONNXBridge

+ (instancetype)sharedBridge {
    static SupertonicONNXBridge *sharedBridge = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedBridge = [[self alloc] init];
    });
    return sharedBridge;
}

- (NSURL *)synthesizeText:(NSString *)text
                voiceName:(NSString *)voiceName
             languageCode:(NSString *)languageCode
             modelRootURL:(NSURL *)modelRootURL
                    error:(NSError **)error {
    if (text.length == 0) {
        if (error) {
            *error = SupertonicMakeError(@"Supertonic requires non-empty text.");
        }
        return nil;
    }

    try {
        const std::string rootKey = SupertonicPathString(modelRootURL);
        std::shared_ptr<SupertonicTextToSpeech> engine;
        auto engineIt = _engineCache.find(rootKey);
        if (engineIt != _engineCache.end()) {
            engine = engineIt->second;
        } else {
            NSError *engineError = nil;
            engine = SupertonicLoadEngine(modelRootURL, &engineError);
            if (engine == nil) {
                if (error) {
                    *error = engineError ?: SupertonicMakeError(@"Failed to load the Supertonic engine.");
                }
                return nil;
            }
            _engineCache.emplace(rootKey, engine);
        }

        const std::string styleKey = rootKey + "/" + std::string(voiceName.UTF8String ?: "");
        std::shared_ptr<SupertonicStyle> style;
        auto styleIt = _styleCache.find(styleKey);
        if (styleIt != _styleCache.end()) {
            style = styleIt->second;
        } else {
            NSError *styleError = nil;
            style = SupertonicLoadStyle(modelRootURL, voiceName, &styleError);
            if (style == nil) {
                if (error) {
                    *error = styleError ?: SupertonicMakeError(@"Failed to load the Supertonic voice style.");
                }
                return nil;
            }
            _styleCache.emplace(styleKey, style);
        }

        std::vector<float> wav = engine->synthesize(text, languageCode, *style);
        NSError *writeError = nil;
        NSURL *outputURL = SupertonicWriteWaveFile(wav, static_cast<double>(engine->sampleRate()), &writeError);
        if (outputURL == nil) {
            if (error) {
                *error = writeError ?: SupertonicMakeError(@"Failed to write the synthesized WAV file.");
            }
            return nil;
        }

        return outputURL;
    } catch (const std::exception &exception) {
        if (error) {
            *error = SupertonicErrorFromException(exception);
        }
        return nil;
    }
}

@end

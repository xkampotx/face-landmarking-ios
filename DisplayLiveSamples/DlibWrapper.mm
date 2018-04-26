//
//  DlibWrapper.m
//  DisplayLiveSamples
//
//  Created by Luis Reisewitz on 16.05.16.
//  Copyright © 2016 ZweiGraf. All rights reserved.
//

#import "DlibWrapper.h"
#import <UIKit/UIKit.h>

#include <dlib/image_processing.h>
#include <dlib/image_io.h>
#include <dlib/opencv.h>

#include <eos/core/Mesh.hpp>
#include <eos/core/LandmarkMapper.hpp>
#include <eos/morphablemodel/EdgeTopology.hpp>
#include <eos/morphablemodel/MorphableModel.hpp>
#include <eos/morphablemodel/Blendshape.hpp>
#include <eos/fitting/fitting.hpp>
#include <eos/cpp17/optional.hpp>
#include <eos/render/draw_utils.hpp>
#include <eos/render/texture_extraction.hpp>
#include <Core>

// for performance debugging
// #define TICK NSDate *startTime = [NSDate date]
// #define TOCK NSLog(@"Time: %f", -[startTime timeIntervalSinceNow])

@implementation DlibWrapper {
    dlib::shape_predictor sp;
    eos::morphablemodel::MorphableModel morphableModel;
    eos::core::LandmarkMapper landmarkMapper;
    eos::morphablemodel::EdgeTopology edgeTopology;
    eos::fitting::ModelContour modelContour;
    eos::fitting::ContourLandmarks contourLandmarks;
    std::vector<eos::morphablemodel::Blendshape> blendshapes;
    eos::core::LandmarkCollection<Eigen::Vector2f> landmarks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self prepare];
    }
    return self;
}

- (void)prepare {
    NSBundle* bundle = [NSBundle mainBundle];
    NSString *modelFileName = [bundle pathForResource:@"shape_predictor_68_face_landmarks" ofType:@"dat"];
    std::string modelFileNameCString = [modelFileName UTF8String];

    dlib::deserialize(modelFileNameCString) >> sp;

    NSString* morphableModelFileName = [bundle pathForResource:@"sfm_shape_3448" ofType:@"bin"];
    morphableModel = eos::morphablemodel::load_model([morphableModelFileName UTF8String]);

    NSString* mappingsFileName = [bundle pathForResource:@"ibug_to_sfm" ofType:@"txt"];
    landmarkMapper = eos::core::LandmarkMapper([mappingsFileName UTF8String]);
    contourLandmarks = eos::fitting::ContourLandmarks::load([mappingsFileName UTF8String]);

    NSString* topologyFileName = [bundle pathForResource:@"sfm_3448_edge_topology" ofType:@"json"];
    edgeTopology = eos::morphablemodel::load_edge_topology([topologyFileName UTF8String]);

    NSString* moduleContourFileName = [bundle pathForResource:@"sfm_model_contours" ofType:@"json"];
    modelContour = eos::fitting::ModelContour::load([moduleContourFileName UTF8String]);

    NSString* blendshapesFileName = [bundle pathForResource:@"expression_blendshapes_3448" ofType:@"bin"];
    blendshapes = eos::morphablemodel::load_blendshapes([blendshapesFileName UTF8String]);
    const int partsCount = 68;
    landmarks.reserve(partsCount);
    for (int i = 0; i < partsCount; i++) {
        eos::core::Landmark<Eigen::Vector2f> landmark;
        landmark.name = std::to_string(i + 1);
        landmarks.emplace_back(landmark);
    }
}

- (void)doWorkOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    char *baseBuffer = (char *)CVPixelBufferGetBaseAddress(imageBuffer);

    int width = (int)CVPixelBufferGetWidth(imageBuffer);
    int height = (int)CVPixelBufferGetHeight(imageBuffer);
    cv::Mat cvImage(height, width, CV_8UC4, baseBuffer, CVPixelBufferGetBytesPerRow(imageBuffer));
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

    cv::Mat coloredImage;
    cv::cvtColor(cvImage, coloredImage, cv::COLOR_BGRA2BGR);

    dlib::array2d<dlib::bgr_pixel> img;
    dlib::assign_image(img, dlib::cv_image<dlib::bgr_pixel>(coloredImage));

    if (rects.count > 0) {
        dlib::full_object_detection shape = sp(img, [self dlibRectFrom: [[rects firstObject] CGRectValue]]);
        for (unsigned long k = 0; k < shape.num_parts(); k++) {
            dlib::point p = shape.part(k);
            int x = (int)p.x() - 1;
            int y = (int)p.y() - 1;
            auto& landmark = landmarks.at(k);
            landmark.coordinates[0] = x;
            landmark.coordinates[1] = y;

            cv::circle(coloredImage, cv::Point(x, y), 4, {0, 0, 0});
        }
    }

    eos::core::Mesh mesh;
    eos::fitting::RenderingParameters renderingParams;
    std::tie(mesh, renderingParams) = eos::fitting::fit_shape_and_pose(morphableModel, blendshapes, landmarks, landmarkMapper, coloredImage.cols, coloredImage.rows, edgeTopology, contourLandmarks, modelContour, 1, eos::cpp17::nullopt, 100000);
    const auto viewport = eos::fitting::get_opencv_viewport(coloredImage.cols, coloredImage.rows);
    // default draw method
    eos::render::draw_wireframe(coloredImage, mesh, renderingParams.get_modelview(), renderingParams.get_projection(), viewport);
    // alternative draw method: https://github.com/headupinclouds/hunter_eos_example/blob/master/eos-dlib-test.cpp

    const auto rotation = renderingParams.get_rotation();
    const float pitchAngle = glm::degrees(glm::pitch(rotation));
    const float yawAngle = glm::degrees(glm::yaw(rotation));
    const float rollAngle = glm::degrees(glm::roll(rotation));

    std::cout << "pitch: " << pitchAngle << "; yaw: " << yawAngle << "; roll: " << rollAngle << std::endl;

    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    const auto data = coloredImage.data;
    const int channels = coloredImage.channels();
    const int widthAndChannels = width * channels;

    long position = 0;
    for (int i = 0; i < height; i++) {
        const int widthIndex = i * widthAndChannels;
        for (int j = 0; j < width; j++) {
            const long location = position * 4;
            const int index = widthIndex + j * channels;
            baseBuffer[location] = data[index];
            baseBuffer[location + 1] = data[index + 1];
            baseBuffer[location + 2] = data[index + 2];
            position++;
        }
    }

    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}

- (dlib::rectangle) dlibRectFrom:(CGRect)rect {
    long left = rect.origin.x;
    long top = rect.origin.y;
    long right = left + rect.size.width;
    long bottom = top + rect.size.height;
    return dlib::rectangle(left, top, right, bottom);
}

@end

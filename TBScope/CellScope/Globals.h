#ifndef GLOBALS_H
#define GLOBALS_H

#include <CoreFoundation/CoreFoundation.h>
#include <opencv2/opencv.hpp>
#include <stdlib.h>
#include <unordered_map>

#define PATCHSZ 28
#define PATCH_WIDTH 48
#define PATCH_HEIGHT 48
#define SPRITESHEET_PATCHES_PER_ROW 25
#define SPRITESHEET_BORDER_WIDTH 2
#define CIRCLEMASKRADIUS 790

#if __APPLE__
#else // Assumed to be windows
#define M_PI 3.1415926
#endif

typedef std::unordered_map<std::string, cv::Mat> MatDict;
typedef std::vector<cv::Point> ContourType;
typedef std::vector<ContourType> ContourContainerType;

#endif

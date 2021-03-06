//
//  ResultsViewController.m
//  CellScope
//
//  Created by Frankie Myers on 11/1/13.
//  Copyright (c) 2013 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "ResultsTabBarController.h"

//TODO: need to display patient/slide metadata somehow (at least from list)...maybe new tab, or maybe all on 1st tab


@implementation ResultsTabBarController

- (void)viewDidLoad
{
    [super viewDidLoad];
    

    [[self.tabBar.items objectAtIndex:0] setTitle:NSLocalizedString(@"Diagnosis", nil)];
    [[self.tabBar.items objectAtIndex:1] setTitle:NSLocalizedString(@"Follow-Up", nil)];
    
    //TODO: only show image view if user has permission.  also tailor slide diagnosis view accordingly
    
    NSMutableArray* tabVCs = [[NSMutableArray alloc] init];
    
    SlideDiagnosisViewController* slideDiagnosisVC = (SlideDiagnosisViewController*)(self.viewControllers[0]);
    slideDiagnosisVC.currentExam = self.currentExam;
    [tabVCs addObject:slideDiagnosisVC];
    
    FollowUpViewController* followUpVC = (FollowUpViewController*)(self.viewControllers[1]);
    followUpVC.currentExam = self.currentExam;
    [tabVCs addObject:followUpVC];
    
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"TBScopeStoryboard" bundle: nil];
    
    if (self.currentExam.examSlides.count>0) {
        ImageResultViewController *imageResultsVC1 = [storyboard instantiateViewControllerWithIdentifier:@"ImageResultViewController"];
        imageResultsVC1.currentSlide = (Slides*)self.currentExam.examSlides[0];
        imageResultsVC1.tabBarItem.title = [NSString stringWithFormat:NSLocalizedString(@"Slide %d", nil),1];
        imageResultsVC1.tabBarItem.image = [UIImage imageNamed:@"slide1icon.png"];
        [tabVCs addObject:imageResultsVC1];
    }
    if (self.currentExam.examSlides.count>1) {
        ImageResultViewController *imageResultsVC2 = [storyboard instantiateViewControllerWithIdentifier:@"ImageResultViewController"];
        imageResultsVC2.currentSlide = (Slides*)self.currentExam.examSlides[1];
        imageResultsVC2.tabBarItem.title = [NSString stringWithFormat:NSLocalizedString(@"Slide %d", nil),2];
        imageResultsVC2.tabBarItem.image = [UIImage imageNamed:@"slide2icon.png"];
        [tabVCs addObject:imageResultsVC2];
    }
    if (self.currentExam.examSlides.count>2) {
        ImageResultViewController *imageResultsVC3 = [storyboard instantiateViewControllerWithIdentifier:@"ImageResultViewController"];
        imageResultsVC3.currentSlide = (Slides*)self.currentExam.examSlides[2];
        imageResultsVC3.tabBarItem.title = [NSString stringWithFormat:NSLocalizedString(@"Slide %d", nil),3];
        imageResultsVC3.tabBarItem.image = [UIImage imageNamed:@"slide3icon.png"];
        [tabVCs addObject:imageResultsVC3];
    }
    

    self.viewControllers = tabVCs;
    
}



- (IBAction)done:(id)sender
{
    [[self navigationController] popToRootViewControllerAnimated:YES];
}

@end

# Dayflow Product Metrics Strategy

## 1. Defining "Active" for Dayflow

Given Dayflow's unique dual nature (passive recording + active viewing), we need a multi-dimensional activity definition:

### Primary Active User Definitions
- **Recording Active**: User has recording enabled for at least 1 hour in a day (app running in background)
- **Viewing Active**: User interacts with the app UI in a meaningful way:
  - Views the timeline (ContentView)
  - Navigates to Dashboard, Settings, or Debug tabs
  - Clicks on a timeline card to see details
  - Hovers to view video previews
  - NOT counted: Just having the app window open in background
- **True DAU**: User qualifies as either Recording Active OR Viewing Active

### User Engagement Levels
- **Passive User**: Only recording, never viewing (≥1 hour recorded/day)
- **Light User**: Recording + views timeline 1-2x per week
- **Regular User**: Recording + views timeline 3-4x per week
- **Power User**: Recording + views timeline daily + uses features like search/export

## 2. Key Metrics Framework

### Core Engagement Metrics
```
Recording Coverage Rate = Hours Recorded / Hours Computer Active
Timeline Interaction Rate = Timeline Views / Recording Days
Feature Adoption Rate = Users Using Feature / Total Active Users
Session Depth = Average Timeline Cards Viewed per Session
Time to First Value = Time from Install to First Timeline View
```

### Retention Metrics
- **D1/D7/D30 Recording Retention**: % still recording after X days
- **D1/D7/D30 Viewing Retention**: % who viewed timeline after X days
- **Recording Consistency**: Average days recorded per week
- **Viewing Habit Formation**: Users viewing 3+ days in last 7 days

## 3. Productivity App-Specific Metrics

### Value Realization
- **Insight Discovery Rate**: Users who view detailed summaries / Total viewers
- **Category Usage**: % of users who customize categories
- **Time Awareness Score**: Before/after survey on time perception
- **Productivity Insights Generated**: Number of AI summaries viewed
- **Export/Share Rate**: Users who export timelapses or summaries

### Background App Health
- **Recording Uptime**: % of intended recording time actually captured
- **Error Recovery Rate**: Successful auto-restarts after errors
- **Storage Efficiency**: GB used per week of recording
- **Performance Impact**: CPU/Memory usage during recording

## 4. Feature-Specific Success Metrics

### Timeline View
- Click-through rate on timeline cards
- Average scroll depth
- Time spent reviewing past days
- Search query frequency
- Video preview engagement rate

### AI Analysis (Current)
- Batch processing success rate
- Category accuracy (based on user corrections)
- Summary quality (implicit through viewing time)
- Processing latency (time from recording to timeline card)

### Viral Features (Upcoming)
- **Share Initiation Rate**: Users who start share flow / MAU
- **Share Completion Rate**: Completed shares / initiated shares
- **Viral Coefficient**: New installs from shares / sharing users
- **Share Medium Distribution**: Which platforms drive most shares
- **Content Type Performance**: Which share formats get most engagement

## 5. Cohort Analysis Strategy

### Segmentation Dimensions

**By Onboarding Path:**
- Full permissions (Screen + Accessibility)
- Screen only
- Launch at login enabled/disabled

**By Usage Pattern:**
- Work hours only (9-5 recording)
- Always-on recording
- Sporadic recording

**By User Type:**
- Individual users
- Team/Enterprise users (future)
- Free vs Premium (future)

### Key Cohort Analyses
- Retention curves by permission level
- Feature adoption by recording consistency
- Storage usage by device type
- Viewing frequency by total hours recorded
- Share propensity by engagement level

## 6. North Star Metric

### Recommended: Weekly Engaged Minutes (WEM)

**Definition**: Total minutes spent viewing timeline content per user per week

**Why this metric:**
- Captures actual value delivery (not just passive recording)
- Encourages regular engagement without being too aggressive
- Balances growth with genuine usage
- Easy to understand and optimize for

**Supporting Metrics:**
1. Recording Coverage: % of active computer time captured
2. Insight Generation Rate: AI summaries viewed / days recorded
3. Habit Formation Score: % of users viewing 3+ times per week

## 7. Implementation Approach

### Analytics Infrastructure

```swift
// Core events to track
enum DayflowEvent: String {
    // Lifecycle
    case appLaunched = "app_launched"
    case windowFocused = "window_focused"  // User brings window to front
    case windowBackgrounded = "window_backgrounded"
    
    // Recording
    case recordingStarted = "recording_started"
    case recordingStopped = "recording_stopped"
    case recordingError = "recording_error"
    
    // Viewing (meaningful interactions only)
    case timelineViewed = "timeline_viewed"  // User scrolls or interacts
    case cardClicked = "card_clicked"  // User clicks to expand
    case cardHovered = "card_hovered"  // User hovers for details
    case videoPreviewPlayed = "video_preview_played"
    case tabSwitched = "tab_switched"  // Dashboard, Settings, etc.
    
    // Features
    case categoryCustomized = "category_customized"
    case shareInitiated = "share_initiated"
    case shareCompleted = "share_completed"
}
```

### Privacy Considerations
- All metrics anonymized by default
- Opt-in for detailed analytics
- Local storage with batch upload
- Clear data retention policy (90 days)
- GDPR/CCPA compliant implementation

### Dashboard Requirements

**Real-time Metrics (< 1 hour delay):**
- Current recording sessions
- Error rate
- Server health (for future cloud features)

**Daily Metrics:**
- DAU (recording + viewing)
- New user activations
- Feature usage counts
- Share metrics

**Weekly/Monthly Metrics:**
- Retention cohorts
- Feature adoption trends
- North star metric trend
- User segmentation analysis

## 8. Measurement Tools

### Recommended Stack
1. **Product Analytics**: PostHog (self-hosted) or Mixpanel
2. **Error Tracking**: Sentry
3. **Local Analytics**: SQLite with privacy-preserving aggregation
4. **Dashboards**: Metabase or custom admin panel

### Implementation Timeline
- Week 1-2: Basic event tracking infrastructure
- Week 3-4: Core metrics dashboard
- Week 5-6: Cohort analysis setup
- Week 7-8: Feature-specific metrics
- Ongoing: Iterate based on learnings

## 9. Success Indicators

### Short-term (3 months)
- 50% D7 recording retention
- 30% weekly viewing rate
- 20% feature adoption rate

### Medium-term (6 months)
- 40% D30 recording retention
- 50% weekly viewing rate
- WEM growing 10% month-over-month

### Long-term (12 months)
- 60% of users are "Regular" or "Power" users
- Viral coefficient > 0.5
- 70% of users report improved time awareness

## 10. Review Cadence

- **Daily**: Recording uptime, error rates, new users
- **Weekly**: DAU/WAU, feature adoption, share metrics
- **Monthly**: Retention cohorts, north star trend, user segments
- **Quarterly**: User surveys, productivity impact studies, strategy review

This metrics strategy ensures Dayflow can measure what matters while respecting user privacy and the unique nature of a background productivity application.
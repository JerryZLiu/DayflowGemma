#!/usr/bin/env python3
"""Two-pass activity card generation with merge logic"""

import json
import time
from datetime import datetime
from pathlib import Path
from process_videos import VideoProcessor, Observation, ActivityCard
from dataclasses import asdict
from typing import Optional, List

class ActivityCardMerger:
    def __init__(self, processor: VideoProcessor):
        self.processor = processor
        
    def should_merge_cards(self, previous_card: ActivityCard, new_card: ActivityCard, debug_dir: Optional[Path] = None) -> bool:
        """Determine if two activity cards should be merged"""
        
        # Quick keyword check - if certain words appear, don't merge
        distraction_keywords = ['youtube', 'instagram', 'twitter', 'reddit', 'facebook', 
                               'cat video', 'dog video', 'social media', 'took a break',
                               'watched', 'scrolled', 'distracted']
        
        combined_text = (previous_card.title + previous_card.summary + 
                        new_card.title + new_card.summary).lower()
        
        for keyword in distraction_keywords:
            if keyword in combined_text:
                print(f"   Merge decision: False - Found distraction keyword: {keyword}")
                return False
        
        merge_prompt = f"""Look at these two consecutive activity periods and decide if they should be combined into one card.

Previous activity ({previous_card.start_time} - {previous_card.end_time}):
Title: {previous_card.title}
Summary: {previous_card.summary}

New activity ({new_card.start_time} - {new_card.end_time}):
Title: {new_card.title}
Summary: {new_card.summary}

Should these be combined? ONLY combine if ALL of these are true:
- They are the SAME TYPE of activity (e.g., both coding, both watching videos)
- They are working on the SAME specific task/project
- BOTH activities are primarily focused (minimal distractions)
- There's a smooth continuation with no major interruptions

DO NOT combine if ANY of these are true:
- One is work and the other is entertainment/break
- Either activity mentions significant distractions (YouTube, social media, etc.)
- They involve different projects or different stages (e.g., coding vs testing)
- There's any mention of taking a break or switching context

Return JSON:
{{
  "combine": true or false,
  "reason": "Brief explanation"
}}"""
        
        try:
            response = self.processor._call_ollama(merge_prompt, [], format_json=True)
            
            # Save debug output
            if debug_dir:
                debug_file = debug_dir / f"merge_check_{int(time.time())}.txt"
                with open(debug_file, 'w') as f:
                    f.write(f"Merge check prompt:\n{merge_prompt}\n\nResponse:\n{response}")
            
            result = self.processor._parse_json_from_response(response, dict)
            should_combine = result.get('combine', False)
            reason = result.get('reason', 'No reason provided')
            print(f"   Merge decision: {should_combine} - {reason}")
            return should_combine
        except Exception as e:
            print(f"Error in merge check: {e}")
            return False
    
    def merge_two_cards(self, previous_card: ActivityCard, new_card: ActivityCard) -> ActivityCard:
        """Merge two cards into one with updated title and summary"""
        
        merge_prompt = f"""Create a single activity card that covers both time periods.

Activity 1 ({previous_card.start_time} - {previous_card.end_time}):
Title: {previous_card.title}
Summary: {previous_card.summary}

Activity 2 ({new_card.start_time} - {new_card.end_time}):
Title: {new_card.title}  
Summary: {new_card.summary}

Create a unified title and summary that covers the entire period from {previous_card.start_time} to {new_card.end_time}.

Title guidelines:
- Natural, conversational (5-10 words)
- Cover the main activities across both periods
- Don't just list both titles - synthesize them

Summary guidelines:
- First person without "I"
- 2-3 sentences maximum
- Tell the complete story from start to finish

Return JSON:
{{
  "title": "Your merged title",
  "summary": "Your merged summary"
}}"""
        
        try:
            response = self.processor._call_ollama(merge_prompt, [], format_json=True)
            result = self.processor._parse_json_from_response(response, dict)
            
            return ActivityCard(
                start_time=previous_card.start_time,  # Keep original start
                end_time=new_card.end_time,          # Use new end
                category=previous_card.category,      # Keep original category for now
                title=result.get('title', f"{previous_card.title} and {new_card.title}"),
                summary=result.get('summary', f"{previous_card.summary} {new_card.summary}")
            )
        except Exception as e:
            print(f"Error merging cards: {e}")
            # Fallback: just extend the time range
            return ActivityCard(
                start_time=previous_card.start_time,
                end_time=new_card.end_time,
                category=previous_card.category,
                title=previous_card.title,
                summary=f"{previous_card.summary} Continued with {new_card.summary}"
            )

def process_with_merging(observations_file: str):
    """Process observations with card merging logic"""
    
    # Load observations
    with open(observations_file, 'r') as f:
        all_observations = json.load(f)
    
    # Sort by time
    all_observations.sort(key=lambda x: x['start_ts'])
    
    # Process in 15-minute chunks
    processor = VideoProcessor()
    merger = ActivityCardMerger(processor)
    
    chunk_duration = 15 * 60  # 15 minutes
    start_time = all_observations[0]['start_ts']
    end_time = all_observations[-1]['end_ts']
    
    final_cards = []
    previous_card = None
    
    chunk_start = start_time
    while chunk_start < end_time:
        chunk_end = chunk_start + chunk_duration
        
        # Get observations for this chunk
        chunk_observations = [
            obs for obs in all_observations
            if obs['start_ts'] < chunk_end and obs['end_ts'] > chunk_start
        ]
        
        if not chunk_observations:
            chunk_start = chunk_end
            continue
        
        print(f"\n{'='*60}")
        print(f"Processing chunk: {datetime.fromtimestamp(chunk_start).strftime('%I:%M %p')} - {datetime.fromtimestamp(chunk_end).strftime('%I:%M %p')}")
        
        # Convert to Observation objects
        obs_objects = [
            Observation(
                start_ts=obs['start_ts'],
                end_ts=obs['end_ts'],
                observation=obs['observation'],
                metadata=obs.get('metadata', {})
            ) for obs in chunk_observations
        ]
        
        # Generate card for this chunk
        debug_dir = Path("debug_output/merging_test")
        debug_dir.mkdir(parents=True, exist_ok=True)
        
        cards = processor._generate_activity_cards(obs_objects, debug_dir)
        if not cards:
            chunk_start = chunk_end
            continue
            
        new_card = cards[0]
        print(f"Generated card: {new_card.title}")
        
        # Check if we should merge with previous card
        if previous_card:
            print(f"Checking merge with previous: {previous_card.title}")
            
            if merger.should_merge_cards(previous_card, new_card, debug_dir):
                print("→ Merging cards")
                merged_card = merger.merge_two_cards(previous_card, new_card)
                print(f"→ Merged title: {merged_card.title}")
                
                # Replace the previous card with merged version
                if final_cards and final_cards[-1] == previous_card:
                    final_cards[-1] = merged_card
                    previous_card = merged_card
                else:
                    final_cards.append(merged_card)
                    previous_card = merged_card
            else:
                print("→ Keeping separate")
                final_cards.append(new_card)
                previous_card = new_card
        else:
            # First card
            final_cards.append(new_card)
            previous_card = new_card
        
        chunk_start = chunk_end
    
    # Display final results
    print(f"\n{'='*60}")
    print(f"FINAL CARDS ({len(final_cards)} total):")
    for i, card in enumerate(final_cards):
        print(f"\n{i+1}. {card.start_time} - {card.end_time}")
        print(f"   Title: {card.title}")
        print(f"   Summary: {card.summary}")

if __name__ == "__main__":
    # Test with observations file from command line or default
    import sys
    obs_file = sys.argv[1] if len(sys.argv) > 1 else "messy_observations.json"
    process_with_merging(obs_file)
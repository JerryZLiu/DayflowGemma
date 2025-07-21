#!/usr/bin/env python3
"""Process dummy observations in 15-minute chunks with historical context"""

import json
from datetime import datetime
from pathlib import Path
from process_videos import VideoProcessor, Observation, ActivityCard
from dataclasses import asdict

def process_observations_in_chunks(observations, chunk_duration_minutes=15, context_duration_minutes=30):
    """Process observations in chunks with historical context"""
    
    # Sort observations by start time
    observations.sort(key=lambda x: x['start_ts'])
    
    # Find the time range
    start_time = observations[0]['start_ts']
    end_time = observations[-1]['end_ts']
    
    # Process in chunks
    processor = VideoProcessor()
    chunk_start = start_time
    all_cards = []
    
    while chunk_start < end_time:
        chunk_end = chunk_start + (chunk_duration_minutes * 60)
        
        # Get observations for this chunk
        chunk_observations = [
            obs for obs in observations
            if obs['start_ts'] < chunk_end and obs['end_ts'] > chunk_start
        ]
        
        if not chunk_observations:
            chunk_start = chunk_end
            continue
            
        # Get context: last 30 minutes of observations and cards
        context_start = chunk_start - (context_duration_minutes * 60)
        context_observations = [
            obs for obs in observations
            if obs['start_ts'] >= context_start and obs['end_ts'] <= chunk_start
        ]
        
        context_cards = [
            card for card in all_cards
            if card.start_time  # Cards from previous chunks
        ]
        
        print(f"\n{'='*60}")
        print(f"Processing chunk: {datetime.fromtimestamp(chunk_start).strftime('%I:%M %p')} - {datetime.fromtimestamp(chunk_end).strftime('%I:%M %p')}")
        print(f"Observations in chunk: {len(chunk_observations)}")
        print(f"Context observations: {len(context_observations)}")
        print(f"Context cards: {len(context_cards)}")
        
        # Convert to Observation objects
        chunk_obs_objects = [
            Observation(
                start_ts=obs['start_ts'],
                end_ts=obs['end_ts'],
                observation=obs['observation'],
                metadata=obs.get('metadata', {})
            ) for obs in chunk_observations
        ]
        
        # Generate activity cards with context
        cards = processor._generate_activity_cards_with_context(
            chunk_obs_objects, 
            context_observations,
            context_cards,
            Path("debug_output/dummy")
        )
        
        print(f"Generated {len(cards)} cards:")
        for card in cards:
            print(f"  - {card.start_time} to {card.end_time}: {card.title}")
        
        all_cards.extend(cards)
        chunk_start = chunk_end
    
    return all_cards

# Extend VideoProcessor to handle context
def _generate_activity_cards_with_context(self, observations, context_observations, context_cards, debug_dir):
    """Generate activity cards with historical context"""
    
    debug_dir.mkdir(parents=True, exist_ok=True)
    
    # Convert observations to transcript format
    transcript_lines = []
    
    # Add context if available
    if context_observations or context_cards:
        transcript_lines.append("=== CONTEXT FROM LAST 30 MINUTES ===")
        
        if context_observations:
            transcript_lines.append("\nPrevious observations:")
            for obs in context_observations:
                start_time = datetime.fromtimestamp(obs['start_ts']).strftime("%-I:%M %p")
                end_time = datetime.fromtimestamp(obs['end_ts']).strftime("%-I:%M %p")
                transcript_lines.append(f"[{start_time} - {end_time}]: {obs['observation']}")
        
        if context_cards:
            transcript_lines.append("\nPrevious activity summaries:")
            for card in context_cards:
                transcript_lines.append(f"[{card.start_time} - {card.end_time}]: {card.title} - {card.summary}")
        
        transcript_lines.append("\n=== CURRENT 15-MINUTE SEGMENT ===")
    
    # Add current observations
    for obs in observations:
        start_time = datetime.fromtimestamp(obs.start_ts).strftime("%-I:%M %p")
        end_time = datetime.fromtimestamp(obs.end_ts).strftime("%-I:%M %p")
        transcript_lines.append(f"[{start_time} - {end_time}]: {obs.observation}")
    
    transcript_text = "\n".join(transcript_lines)
    
    # Save the full context for debugging
    context_file = debug_dir / "activity_context.txt"
    with open(context_file, 'w') as f:
        f.write(transcript_text)
    
    # Use the existing method but with our enhanced transcript
    # We'll need to temporarily override the prompt
    original_method = self._generate_activity_cards
    
    # Create a modified version that uses our transcript
    def modified_generate(obs, debug):
        # The original method builds its own transcript, but we want to use ours
        # So we'll call the LLM directly
        activity_prompt = f"""You are a digital anthropologist, observing a user's activity log. Your goal is to synthesize this log into timeline cards that tell the story of their session.

{transcript_text}

Your task: Create ONE activity card that summarizes the CURRENT 15-MINUTE SEGMENT.
Note: The context helps you understand what the user was doing before, but focus your card on the current segment.

Rules:
1. Use the earliest start time from the CURRENT SEGMENT observations
2. Use the latest end time from the CURRENT SEGMENT observations
3. Pick the MOST DOMINANT category from the activities in the CURRENT SEGMENT
4. Write a natural, conversational title (5-10 words)
5. Summarize what happened in the CURRENT SEGMENT in one sentence

Categories to use (pick ONLY ONE per card):
- Work: Professional tasks, coding, documentation
- Research: Learning, reading articles, watching tutorials
- Communication: Email, messaging, social media interactions
- Entertainment: Casual browsing, videos, social media consumption
- Administrative: Account management, billing, settings

Return EXACTLY ONE activity card:
[
  {{
    "startTime": "H:MM AM/PM",
    "endTime": "H:MM AM/PM", 
    "category": "Category name",
    "title": "Natural title describing the activity",
    "summary": "One sentence summary"
  }}
]"""
        
        try:
            response = self._call_ollama(activity_prompt, [], format_json=True)
            cards_data = self._parse_json_from_response(response, list)
            
            # Save raw response
            raw_response_file = debug_dir / "activity_cards_raw_response.txt"
            with open(raw_response_file, 'w') as f:
                f.write(response)
            
            cards = []
            for card_data in cards_data:
                cards.append(ActivityCard(
                    start_time=card_data['startTime'],
                    end_time=card_data['endTime'],
                    category=card_data['category'],
                    title=card_data['title'],
                    summary=card_data['summary']
                ))
            
            return cards
            
        except Exception as e:
            print(f"Error generating cards: {e}")
            # Fallback
            return [ActivityCard(
                start_time=datetime.fromtimestamp(observations[0].start_ts).strftime("%-I:%M %p"),
                end_time=datetime.fromtimestamp(observations[-1].end_ts).strftime("%-I:%M %p"),
                category="Work",
                title="Activity Session",
                summary="User engaged in various activities."
            )]
    
    return modified_generate(observations, debug_dir)

# Monkey patch the method
VideoProcessor._generate_activity_cards_with_context = _generate_activity_cards_with_context

if __name__ == "__main__":
    # Load dummy observations
    with open("dummy_observations.json", "r") as f:
        observations = json.load(f)
    
    # Process in chunks
    cards = process_observations_in_chunks(observations)
    
    print(f"\n{'='*60}")
    print(f"FINAL SUMMARY: Generated {len(cards)} activity cards total")
    for i, card in enumerate(cards):
        print(f"{i+1}. {card.start_time} - {card.end_time} ({card.category}): {card.title}")
        print(f"   {card.summary}")
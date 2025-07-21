#!/usr/bin/env python3
"""
Video Processing Pipeline with Ollama
Processes videos through a two-stage observation generation process.
"""

import json
import logging
import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import List, Tuple, Optional, Dict, Any
import base64
import requests
from PIL import Image
import io

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('video_processing.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Constants
OLLAMA_ENDPOINT = "http://localhost:1234"
OLLAMA_MODEL = "google/gemma-3n-e4b"
FRAME_EXTRACTION_INTERVAL = 30  # seconds
DEBUG_DIR = Path("debug_output")
DEBUG_DIR.mkdir(exist_ok=True)


@dataclass
class FrameData:
    """Represents an extracted frame with metadata"""
    image_base64: str
    timestamp: float  # seconds from video start
    frame_number: int


@dataclass
class VideoSegment:
    """Represents a merged video segment observation"""
    start_timestamp: str  # MM:SS format
    end_timestamp: str    # MM:SS format
    description: str


@dataclass
class Observation:
    """Final observation format"""
    start_ts: int  # Unix timestamp
    end_ts: int    # Unix timestamp
    observation: str
    metadata: Optional[Dict[str, Any]] = None


@dataclass
class LLMCall:
    """Log of an LLM API call"""
    timestamp: datetime
    latency: float
    input: str
    output: str
    model: str = OLLAMA_MODEL
    error: Optional[str] = None


@dataclass
class ActivityCard:
    """Activity card (stub for now)"""
    start_time: str
    end_time: str
    category: str
    title: str
    summary: str


class VideoProcessor:
    """Main video processing class"""
    
    def __init__(self, ollama_endpoint: str = OLLAMA_ENDPOINT, model: str = OLLAMA_MODEL):
        self.ollama_endpoint = ollama_endpoint
        self.model = model
        self.llm_calls: List[LLMCall] = []
        
    def process_video_list(self, video_list_file: str):
        """Process all videos from a text file list"""
        try:
            with open(video_list_file, 'r') as f:
                video_paths = [line.strip() for line in f if line.strip()]
        except FileNotFoundError:
            logger.error(f"Video list file not found: {video_list_file}")
            return
        
        logger.info(f"Found {len(video_paths)} videos to process")
        
        for i, video_path in enumerate(video_paths, 1):
            logger.info(f"\nProcessing video {i}/{len(video_paths)}: {video_path}")
            try:
                self.process_single_video(video_path)
            except Exception as e:
                logger.error(f"Failed to process {video_path}: {str(e)}", exc_info=True)
                continue
    
    def process_single_video(self, video_path: str) -> Tuple[List[Observation], List[ActivityCard]]:
        """Process a single video through the entire pipeline"""
        video_path = Path(video_path)
        if not video_path.exists():
            raise FileNotFoundError(f"Video file not found: {video_path}")
        
        # Create debug directory for this video
        video_debug_dir = DEBUG_DIR / video_path.stem
        video_debug_dir.mkdir(exist_ok=True)
        
        logger.info(f"Starting processing for: {video_path.name}")
        start_time = time.time()
        
        # Check for cached observations
        obs_file = video_debug_dir / "observations.json"
        cached_obs_file = video_debug_dir / "cached_observations.json"
        
        observations = None
        
        # Try to load cached observations first
        if cached_obs_file.exists():
            logger.info("Found cached observations, loading...")
            try:
                with open(cached_obs_file, 'r') as f:
                    obs_data = json.load(f)
                    observations = [Observation(**obs) for obs in obs_data]
                logger.info(f"Loaded {len(observations)} cached observations")
            except Exception as e:
                logger.warning(f"Failed to load cached observations: {e}")
                observations = None
        
        # If no cached observations, generate them
        if observations is None:
            # Get video duration
            duration = self._get_video_duration(str(video_path))
            logger.info(f"Video duration: {self._format_duration(duration)}")
            
            # Stage 1: Extract frames
            logger.info("Stage 1: Extracting frames...")
            frames = self._extract_frames(str(video_path), video_debug_dir)
            logger.info(f"Extracted {len(frames)} frames")
            
            # Stage 2: Get frame descriptions
            logger.info("Stage 2: Analyzing frames...")
            frame_descriptions = []
            for i, frame in enumerate(frames):
                logger.info(f"Analyzing frame {i+1}/{len(frames)} at {self._format_duration(frame.timestamp)}")
                description = self._get_frame_description(frame, video_debug_dir)
                frame_descriptions.append((frame.timestamp, description))
                
            # Save frame descriptions
            frame_desc_file = video_debug_dir / "frame_descriptions.json"
            with open(frame_desc_file, 'w') as f:
                json.dump([{"timestamp": t, "description": d} for t, d in frame_descriptions], f, indent=2)
            
            # Stage 3: Merge descriptions into observations
            logger.info("Stage 3: Merging frame descriptions...")
            batch_start_time = datetime.now()
            observations = self._merge_frame_descriptions(
                frame_descriptions, 
                batch_start_time, 
                duration,
                video_debug_dir
            )
            logger.info(f"Created {len(observations)} observations")
            
            # Save observations and cache them
            with open(obs_file, 'w') as f:
                json.dump([asdict(obs) for obs in observations], f, indent=2)
            with open(cached_obs_file, 'w') as f:
                json.dump([asdict(obs) for obs in observations], f, indent=2)
        
        # Stage 4: Generate activity cards (stub)
        logger.info("Stage 4: Generating activity cards...")
        activity_cards = self._generate_activity_cards(observations, video_debug_dir)
        logger.info(f"Generated {len(activity_cards)} activity cards")
        
        # Save activity cards
        cards_file = video_debug_dir / "activity_cards.json"
        with open(cards_file, 'w') as f:
            json.dump([asdict(card) for card in activity_cards], f, indent=2)
        
        # Save all LLM calls
        llm_calls_file = video_debug_dir / "llm_calls.json"
        with open(llm_calls_file, 'w') as f:
            json.dump([{
                "timestamp": call.timestamp.isoformat(),
                "latency": call.latency,
                "model": call.model,
                "input": call.input,
                "output": call.output,
                "error": call.error
            } for call in self.llm_calls], f, indent=2)
        
        total_time = time.time() - start_time
        logger.info(f"Total processing time: {total_time:.2f} seconds")
        
        # Clear LLM calls for next video
        self.llm_calls.clear()
        
        return observations, activity_cards
    
    def _get_video_duration(self, video_path: str) -> float:
        """Get video duration in seconds using ffprobe"""
        cmd = [
            'ffprobe', '-v', 'error', '-show_entries', 
            'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1',
            video_path
        ]
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return float(result.stdout.strip())
        except subprocess.CalledProcessError as e:
            logger.error(f"ffprobe failed: {e.stderr}")
            raise
        except ValueError:
            logger.error(f"Invalid duration value: {result.stdout}")
            raise
    
    def _extract_frames(self, video_path: str, debug_dir: Path) -> List[FrameData]:
        """Extract frames from video at specified intervals"""
        frames = []
        duration = self._get_video_duration(video_path)
        
        # Create frames subdirectory
        frames_dir = debug_dir / "frames"
        frames_dir.mkdir(exist_ok=True)
        
        current_time = 0
        frame_number = 0
        
        while current_time < duration:
            output_file = frames_dir / f"frame_{frame_number:04d}.jpg"
            
            # Extract frame using ffmpeg
            cmd = [
                'ffmpeg', '-ss', str(current_time), '-i', video_path,
                '-vframes', '1', '-q:v', '2',  # High quality JPEG
                '-vf', 'scale=iw*2/3:ih*2/3',  # Scale down by 2/3 as in Swift code
                '-y', str(output_file)
            ]
            
            try:
                subprocess.run(cmd, capture_output=True, check=True)
                
                # Convert to base64
                with open(output_file, 'rb') as f:
                    image_data = f.read()
                    image_base64 = base64.b64encode(image_data).decode('utf-8')
                
                frames.append(FrameData(
                    image_base64=image_base64,
                    timestamp=current_time,
                    frame_number=frame_number
                ))
                
                logger.debug(f"Extracted frame at {current_time:.1f}s")
                
            except subprocess.CalledProcessError as e:
                logger.warning(f"Failed to extract frame at {current_time}s: {e.stderr.decode()}")
            
            current_time += FRAME_EXTRACTION_INTERVAL
            frame_number += 1
        
        return frames
    
    def _get_frame_description(self, frame: FrameData, debug_dir: Path) -> str:
        """Get simple description for a single frame using Ollama"""
        prompt = """Describe what's happening in this screenshot. Be specific about the application and task.
Include the app name, website (if browser), and what specific action is being performed.
Answer in one clear, detailed sentence without starting with "User is" or "The user".

Good examples:
- "Writing a project status email in Gmail with spreadsheet attachment open in preview"
- "Coding a React component in VS Code with terminal showing npm errors at bottom"
- "Browsing r/programming on Reddit in Chrome while Slack notifications appear"
- "Watching a Python tutorial on YouTube about data visualization with matplotlib"
- "Reviewing pull request #234 on GitHub, commenting on the authentication changes"
- "Editing a blog post in Notion about productivity tips with formatting toolbar open"
- "In Figma designing a mobile app login screen with color palette on the right"

Bad examples (too vague):
- "Using a web browser"
- "Working on computer"
- "Looking at code"
"""
        
        start_time = time.time()
        
        try:
            response = self._call_ollama(prompt, [frame.image_base64])
            description = response.strip()
            
            # Save individual frame description
            desc_file = debug_dir / "frame_descriptions" / f"frame_{frame.frame_number:04d}_desc.txt"
            desc_file.parent.mkdir(exist_ok=True)
            with open(desc_file, 'w') as f:
                f.write(description)
            
            latency = time.time() - start_time
            self.llm_calls.append(LLMCall(
                timestamp=datetime.now(),
                latency=latency,
                input=f"Frame analysis at {self._format_duration(frame.timestamp)}",
                output=description
            ))
            
            return description
            
        except Exception as e:
            logger.error(f"Failed to get frame description: {str(e)}")
            self.llm_calls.append(LLMCall(
                timestamp=datetime.now(),
                latency=time.time() - start_time,
                input=f"Frame analysis at {self._format_duration(frame.timestamp)}",
                output="",
                error=str(e)
            ))
            return f"[Error analyzing frame at {self._format_duration(frame.timestamp)}]"
    
    def _merge_frame_descriptions(
        self, 
        frame_descriptions: List[Tuple[float, str]], 
        batch_start_time: datetime,
        video_duration: float,
        debug_dir: Path
    ) -> List[Observation]:
        """Merge frame descriptions into coherent observations"""
        
        # Format descriptions for prompt
        formatted_descriptions = []
        for timestamp, description in frame_descriptions:
            time_str = self._format_duration(timestamp)
            formatted_descriptions.append(f"[{time_str}] {description}")
        
        descriptions_text = "\n".join(formatted_descriptions)
        duration_str = self._format_duration(video_duration)
        
        merge_prompt = f"""You have {len(frame_descriptions)} snapshots from a {duration_str} video showing someone's computer usage.

Here are the snapshots:
{descriptions_text}

CRITICAL TASK: Group these snapshots into EXACTLY 2-5 segments. DO NOT create more than 5 segments under any circumstances.

<thinking>
Think step by step:
1. Identify the main activities/themes across all snapshots
2. Find natural breakpoints where the user switches between major tasks
3. Group related activities together even if there are brief interruptions
4. AIM FOR 3-4 SEGMENTS if possible - this is usually the sweet spot
</thinking>

STRICT RULES:
- You MUST create between 2 and 5 segments total (no more, no less)
- Each segment should cover multiple consecutive snapshots
- Brief interruptions should be absorbed into the main activity, not split out
- Segments should tell a coherent story of what was accomplished
- All timestamps MUST be within 00:00 to {duration_str}

Return ONLY a JSON array with 2-5 segments:
[
  {{
    "startTimestamp": "MM:SS",
    "endTimestamp": "MM:SS", 
    "description": "Natural description covering multiple related activities"
  }}
]

Example of GOOD grouping (3 segments covering 15 minutes):
[
  {{
    "startTimestamp": "00:00",
    "endTimestamp": "05:30",
    "description": "Managed Claude.ai billing and payment settings, reviewing subscription costs and updating payment methods. Also initiated financial data processing scripts."
  }},
  {{
    "startTimestamp": "05:30", 
    "endTimestamp": "10:00",
    "description": "Web research session browsing AI-related content on Reflection.ai and social media, with brief detour to check Google Cloud billing alerts."
  }},
  {{
    "startTimestamp": "10:00",
    "endTimestamp": "14:45", 
    "description": "Development work in VS Code and GitHub Desktop, debugging timestamp parsing issues and reviewing pull requests for the Dayflow project."
  }}
]

REMEMBER: Output EXACTLY 2-5 segments. If you output more than 5 segments, you have failed the task."""
        
        start_time = time.time()
        
        try:
            response = self._call_ollama(merge_prompt, [], format_json=True)
            
            # Save raw response for debugging
            raw_response_file = debug_dir / "merge_raw_response.txt"
            with open(raw_response_file, 'w') as f:
                f.write(response)
            
            # Parse JSON response
            segments = self._parse_json_from_response(response, list)
            
            logger.info(f"Parsed {len(segments)} segments from merge response")
            
            # Convert to Observation objects
            observations = []
            for segment in segments:
                start_seconds = self._parse_timestamp(segment['startTimestamp'])
                end_seconds = self._parse_timestamp(segment['endTimestamp'])
                
                start_date = batch_start_time.timestamp() + start_seconds
                end_date = batch_start_time.timestamp() + end_seconds
                
                observations.append(Observation(
                    start_ts=int(start_date),
                    end_ts=int(end_date),
                    observation=segment['description'],
                    metadata={'model': self.model}
                ))
            
            latency = time.time() - start_time
            self.llm_calls.append(LLMCall(
                timestamp=datetime.now(),
                latency=latency,
                input=merge_prompt,
                output=response
            ))
            
            return observations
            
        except Exception as e:
            logger.error(f"Failed to merge descriptions: {str(e)}")
            self.llm_calls.append(LLMCall(
                timestamp=datetime.now(),
                latency=time.time() - start_time,
                input=merge_prompt,
                output="",
                error=str(e)
            ))
            
            # Return single observation as fallback
            return [Observation(
                start_ts=int(batch_start_time.timestamp()),
                end_ts=int(batch_start_time.timestamp() + video_duration),
                observation="Failed to merge frame descriptions",
                metadata={'error': str(e)}
            )]
    
    def _generate_activity_cards(self, observations: List[Observation], debug_dir: Path) -> List[ActivityCard]:
        """Generate activity cards from observations using LLM"""
        logger.info("Generating activity cards from observations...")
        
        # Convert observations to transcript format
        transcript_lines = []
        for obs in observations:
            start_time = datetime.fromtimestamp(obs.start_ts).strftime("%-I:%M %p")
            end_time = datetime.fromtimestamp(obs.end_ts).strftime("%-I:%M %p")
            transcript_lines.append(f"[{start_time} - {end_time}]: {obs.observation}")
        
        transcript_text = "\n".join(transcript_lines)
        
        # Prompt for activity card generation
        activity_prompt = f"""You are observing someone's computer activity from the last 15 minutes.

Here are the observations:
{transcript_text}

Create a title and summary following these guidelines:

Title guidelines:
Write titles like you're texting a friend about what you did. Natural, conversational, direct.
Rules:
- Be specific and clear (not creative or vague)
- Keep it short - aim for 5-10 words
- Include main activity + distraction if relevant
Good examples:
- "Edited photos in Lightroom"
- "Python tutorial on Codecademy"
- "Watched 3 episodes on Netflix"
- "Wrote blog post, kept checking Instagram"
- "Researched flights to Tokyo"
Bad examples:
- "Early morning digital drift" (too vague/poetic)
- "Extended Browsing Session" (too formal)

Summary guidelines:
Write brief factual summaries. First person perspective without "I".
Rules:
- State what happened directly - no lead-ins
- Maximum 2-3 sentences
- Just the facts: what you did, which tools/projects, major blockers
Good examples:
"Refactored the user auth module in React, added OAuth support. Debugged CORS issues with the backend API for an hour."
"Designed new landing page mockups in Figma. Exported assets and started implementing in Next.js before getting pulled into a client meeting."

Return JSON:
{{
  "title": "Your title here",
  "summary": "Your summary here"
}}"""
        
        call_start_time = time.time()
        
        try:
            response = self._call_ollama(activity_prompt, [], format_json=True)
            
            # Save raw response
            raw_response_file = debug_dir / "activity_cards_raw_response.txt"
            with open(raw_response_file, 'w') as f:
                f.write(response)
            
            # Parse JSON response
            result_data = self._parse_json_from_response(response, dict)
            
            logger.info(f"Generated title and summary")
            
            # Create a single activity card using the first and last observation times
            card_start_time = datetime.fromtimestamp(observations[0].start_ts).strftime("%-I:%M %p")
            card_end_time = datetime.fromtimestamp(observations[-1].end_ts).strftime("%-I:%M %p")
            
            # For now, default to "Work" category - we can improve this later
            cards = [ActivityCard(
                start_time=card_start_time,
                end_time=card_end_time,
                category="Work",
                title=result_data.get('title', 'Activity Session'),
                summary=result_data.get('summary', 'User engaged in various activities.')
            )]
            
            latency = time.time() - call_start_time
            self.llm_calls.append(LLMCall(
                timestamp=datetime.now(),
                latency=latency,
                input=activity_prompt,
                output=response
            ))
            
            return cards
            
        except Exception as e:
            logger.error(f"Failed to generate activity cards: {str(e)}")
            self.llm_calls.append(LLMCall(
                timestamp=datetime.now(),
                latency=time.time() - call_start_time,
                input=activity_prompt,
                output="",
                error=str(e)
            ))
            
            # Return simple fallback card
            card_start_time = datetime.fromtimestamp(observations[0].start_ts).strftime("%-I:%M %p")
            card_end_time = datetime.fromtimestamp(observations[-1].end_ts).strftime("%-I:%M %p")
            
            cards = [ActivityCard(
                start_time=card_start_time,
                end_time=card_end_time,
                category="Work",
                title="Activity Session",
                summary="User engaged in various activities."
            )]
            
            return cards
    
    def _call_ollama(self, prompt: str, images: List[str], format_json: bool = False) -> str:
        """Call OpenAI-compatible API"""
        url = f"{self.ollama_endpoint}/v1/chat/completions"
        
        messages = []
        
        # Add system message for JSON format if needed
        if format_json:
            messages.append({
                "role": "system",
                "content": "You must respond with valid JSON only. No explanations or text outside the JSON."
            })
        
        # Add user message with images if provided
        if images:
            # For vision models, we need to format the message with image data
            content = [
                {"type": "text", "text": prompt}
            ]
            for image in images:
                content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{image}"
                    }
                })
            messages.append({
                "role": "user",
                "content": content
            })
        else:
            messages.append({
                "role": "user",
                "content": prompt
            })
        
        request_data = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": -1,
            "stream": False
        }
        
        try:
            response = requests.post(url, json=request_data, timeout=300)  # 5 minute timeout
            response.raise_for_status()
            
            result = response.json()
            return result.get("choices", [{}])[0].get("message", {}).get("content", "")
            
        except requests.exceptions.RequestException as e:
            logger.error(f"API request failed: {str(e)}")
            raise
    
    def _parse_json_from_response(self, response: str, expected_type=None):
        """Parse JSON from LLM response, handling common issues"""
        # Try direct parsing first
        try:
            data = json.loads(response)
            if expected_type and not isinstance(data, expected_type):
                raise ValueError(f"Expected {expected_type}, got {type(data)}")
            return data
        except json.JSONDecodeError:
            pass
        
        # Try to find JSON in the response
        response = response.strip()
        
        # Look for array
        if expected_type == list:
            start_idx = response.find('[')
            end_idx = response.rfind(']')
            if start_idx != -1 and end_idx != -1:
                json_str = response[start_idx:end_idx+1]
                try:
                    return json.loads(json_str)
                except json.JSONDecodeError:
                    pass
        
        # Look for object
        start_idx = response.find('{')
        end_idx = response.rfind('}')
        if start_idx != -1 and end_idx != -1:
            json_str = response[start_idx:end_idx+1]
            try:
                data = json.loads(json_str)
                if expected_type == list:
                    return [data]  # Wrap single object in list
                return data
            except json.JSONDecodeError:
                pass
        
        raise ValueError(f"Could not parse JSON from response: {response[:200]}...")
    
    def _parse_timestamp(self, timestamp: str) -> float:
        """Parse MM:SS or HH:MM:SS timestamp to seconds"""
        parts = timestamp.split(':')
        if len(parts) == 2:
            minutes, seconds = map(int, parts)
            return minutes * 60 + seconds
        elif len(parts) == 3:
            hours, minutes, seconds = map(int, parts)
            return hours * 3600 + minutes * 60 + seconds
        else:
            raise ValueError(f"Invalid timestamp format: {timestamp}")
    
    def _format_duration(self, seconds: float) -> str:
        """Format seconds to MM:SS or HH:MM:SS"""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        
        if hours > 0:
            return f"{hours:02d}:{minutes:02d}:{secs:02d}"
        else:
            return f"{minutes:02d}:{secs:02d}"


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Process videos through Ollama")
    parser.add_argument("video_list", help="Text file containing video paths (one per line)")
    parser.add_argument("--ollama-endpoint", default=OLLAMA_ENDPOINT, help="Ollama API endpoint")
    parser.add_argument("--model", default=OLLAMA_MODEL, help="Ollama model to use")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    
    args = parser.parse_args()
    
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Skip Ollama health check
    logger.info(f"Using Ollama at {args.ollama_endpoint} (health check skipped)")
    
    # Process videos
    processor = VideoProcessor(args.ollama_endpoint, args.model)
    processor.process_video_list(args.video_list)
    
    logger.info("Processing complete!")


if __name__ == "__main__":
    main()
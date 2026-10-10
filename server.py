#!/usr/bin/env python3
"""Local web server and handcrafted typing-practice coach."""

import difflib
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import as_completed
import json
import math
import os
import random
import re
from threading import Lock
from urllib.error import HTTPError
from urllib.error import URLError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote
from urllib.parse import urlsplit
from urllib.request import Request
from urllib.request import urlopen


HOST = "127.0.0.1"
PORT = int(os.environ.get("PORT", "8001"))
APP_DIRECTORY = Path(__file__).resolve().parent
MAX_BODY_BYTES = 12_000
ONLINE_LOOKUP_TIMEOUT = 3.5
OFFLINE_DICTIONARY_PATH = APP_DIRECTORY / "offline_dictionary.json"
OFFLINE_DICTIONARY = json.loads(OFFLINE_DICTIONARY_PATH.read_text(encoding="utf-8"))
OFFLINE_CACHE_PATH = APP_DIRECTORY / "dictionary_cache.json"
OFFLINE_CACHE = json.loads(OFFLINE_CACHE_PATH.read_text(encoding="utf-8"))
OFFLINE_CACHE_LOCK = Lock()
DICTIONARY_STOP_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
    "had", "has", "have", "he", "her", "hers", "him", "his", "i", "if", "in",
    "into", "is", "it", "its", "me", "my", "of", "on", "or", "our", "ours",
    "she", "so", "than", "that", "the", "their", "them", "then", "there",
    "these", "they", "this", "those", "to", "us", "was", "we", "were", "what",
    "when", "where", "which", "who", "will", "with", "you", "your", "yours",
}

EXERCISES = {
    "easy": {
        "accuracy": [
            "A calm pace helps every finger find the right key.",
            "Take your time and type each word with care.",
            "Steady hands make fewer mistakes over time.",
        ],
        "speed": [
            "Quick hands move across the keyboard with ease.",
            "Keep a smooth rhythm as you type each short phrase.",
            "Small steps build speed when practice stays steady.",
        ],
        "punctuation": [
            "Ready, set, type! Keep each mark in place.",
            "One more try: slow down, look, and type.",
            "Can you type this? Yes, you can!",
        ],
        "numbers": [
            "I practice for 5 minutes each day.",
            "There are 12 keys in this short exercise.",
            "Try 3 slow breaths before typing 8 words.",
        ],
    },
    "normal": {
        "accuracy": [
            "Careful practice turns small improvements into reliable habits.",
            "Look ahead at the next word while keeping your hands relaxed.",
            "A consistent rhythm is more useful than rushing through every sentence.",
        ],
        "speed": [
            "Build a comfortable rhythm, then let your fingers move naturally.",
            "Fast typing comes from familiar patterns and relaxed hands.",
            "Keep your eyes on the sentence and allow each word to flow.",
        ],
        "punctuation": [
            "Practice makes progress; accuracy grows with every attempt.",
            "Pause, breathe, and continue: steady work pays off!",
            "Did you notice the comma, question mark, and final period?",
        ],
        "numbers": [
            "A 10-minute practice can improve 2 useful skills.",
            "Type 24 words, pause for 5 seconds, then continue.",
            "The 2026 workshop starts at 3:45 on May 18.",
        ],
    },
    "hard": {
        "accuracy": [
            "Precision matters most when a sentence contains several different patterns.",
            "Stay relaxed, watch the punctuation, and correct mistakes without losing your rhythm.",
            "A dependable typist balances careful attention with a steady pace.",
        ],
        "speed": [
            "Confident typists maintain momentum without sacrificing control or clarity.",
            "Let familiar letter combinations guide your fingers across the keyboard.",
            "Sustained speed is built through focused practice, not tense hands.",
        ],
        "punctuation": [
            "When the timer starts, breathe; then type each phrase—carefully!",
            "Is accuracy improving? Keep practicing, even when the symbols change.",
            "She said, \"Practice daily,\" and added: consistency really matters.",
        ],
        "numbers": [
            "In 2026, 48 students completed 7 exercises in 15 minutes.",
            "A 92% accuracy rate at 68 WPM is a useful starting point.",
            "Enter code 4B-291, then check the 3:07 appointment on June 24.",
        ],
    },
}


class PracticeRequestError(ValueError):
    """A request contains invalid practice data."""


class PracticeServer(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/api/health":
            self.send_json(200, {"status": "ok"})
        elif path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write((APP_DIRECTORY / "index.html").read_bytes())
        else:
            self.send_json(404, {"error": "Not found."})

    def do_POST(self):
        path = urlsplit(self.path).path
        if path not in ("/api/practice", "/api/feedback", "/api/chat"):
            self.send_json(404, {"error": "Not found."})
            return
        try:
            payload = self.read_json_body()
            if path == "/api/practice":
                self.send_json(200, create_exercise(payload))
            elif path == "/api/chat":
                status, response = handle_chat(payload)
                self.send_json(status, response)
            else:
                self.send_json(200, assess_attempt(payload))
        except PracticeRequestError as error:
            self.send_json(400, {"error": str(error)})

    def read_json_body(self):
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise PracticeRequestError("Content-Length must be a number.") from error
        if content_length < 1 or content_length > MAX_BODY_BYTES:
            raise PracticeRequestError("Request body must be between 1 and 12,000 bytes.")
        try:
            payload = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise PracticeRequestError("Request body must contain valid JSON.") from error
        if not isinstance(payload, dict):
            raise PracticeRequestError("Request body must be a JSON object.")
        return payload

    def send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string, *args):
        print(f"{self.address_string()} - {format_string % args}")


def get_choice(payload, key, allowed_values):
    value = payload.get(key)
    if not isinstance(value, str) or value not in allowed_values:
        choices = ", ".join(sorted(allowed_values))
        raise PracticeRequestError(f"{key} must be one of: {choices}.")
    return value


def create_exercise(payload):
    difficulty = get_choice(payload, "difficulty", EXERCISES)
    focus = get_choice(payload, "focus", EXERCISES[difficulty])
    return {
        "prompt": random.choice(EXERCISES[difficulty][focus]),
        "difficulty": difficulty,
        "focus": focus,
    }


def get_content_words(text):
    words = re.findall(r"[a-z]+(?:['’][a-z]+)?", text.lower())
    content_words = []
    for word in words:
        if word not in DICTIONARY_STOP_WORDS and word not in content_words:
            content_words.append(word)
    return content_words or list(dict.fromkeys(words))


def get_offline_definition(word):
    variants = [word]
    if word.endswith("ies") and len(word) > 4:
        variants.append(f"{word[:-3]}y")
    if word.endswith("es") and len(word) > 4:
        variants.append(word[:-2])
    if word.endswith("s") and len(word) > 3:
        variants.append(word[:-1])
    if word.endswith("ing") and len(word) > 5:
        stem = word[:-3]
        variants.extend((stem, f"{stem}e"))
    if word.endswith("ed") and len(word) > 4:
        stem = word[:-2]
        variants.extend((stem, f"{stem}e"))
    for variant in dict.fromkeys(variants):
        definition = OFFLINE_CACHE.get(variant) or OFFLINE_DICTIONARY.get(variant)
        if definition:
            return variant, definition
    return None


def cache_online_definition(word, definitions):
    cached_text = "; ".join(definitions)
    with OFFLINE_CACHE_LOCK:
        OFFLINE_CACHE[word] = cached_text
        try:
            temporary_path = OFFLINE_CACHE_PATH.with_suffix(".tmp")
            temporary_path.write_text(
                json.dumps(OFFLINE_CACHE, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            temporary_path.replace(OFFLINE_CACHE_PATH)
        except OSError as error:
            print(f"Unable to save offline dictionary cache: {error}")


def get_online_definition(word):
    url = f"https://api.dictionaryapi.dev/api/v2/entries/en/{quote(word)}"
    request = Request(url, headers={"User-Agent": "LocalTypingWordHelper/1.0"})
    try:
        with urlopen(request, timeout=ONLINE_LOOKUP_TIMEOUT) as response:
            entries = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        return None, error.code == 404
    except (URLError, TimeoutError, OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None, False
    if not isinstance(entries, list):
        return None, True

    definitions = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        for meaning in entry.get("meanings", []):
            if not isinstance(meaning, dict):
                continue
            part_of_speech = meaning.get("partOfSpeech", "")
            for item in meaning.get("definitions", []):
                if not isinstance(item, dict):
                    continue
                definition = item.get("definition")
                if not isinstance(definition, str) or not definition.strip():
                    continue
                example = item.get("example")
                text = f"{part_of_speech}: {definition.strip()}" if part_of_speech else definition.strip()
                if isinstance(example, str) and example.strip():
                    text += f' Example: “{example.strip()}”'
                definitions.append(text)
                if len(definitions) == 2:
                    return definitions, True
    return (definitions or None), True


def format_definition_reply(query, definitions, mode):
    is_sentence = len(query.split()) > 1
    subject = "sentence" if is_sentence else "word"
    heading = f'Here’s the definition of your {subject}, “{query}”:'
    lines = [heading]
    for word, definition_list in definitions:
        if mode == "offline":
            lines.append(f"{word}: {definition_list}")
        else:
            lines.append(f"{word}: {'; '.join(definition_list)}")
    if mode == "offline":
        lines.append("These definitions came from the bundled offline dictionary.")
    return "\n\n".join(lines)


def define_query(query, mode):
    words = get_content_words(query)
    if mode == "offline":
        definitions = []
        for word in words[:18]:
            result = get_offline_definition(word)
            if result:
                matched_word, definition = result
                definitions.append((word if matched_word == word else f"{word} (base form: {matched_word})", definition))
        if not definitions:
            return 200, {
                "reply": "I couldn’t find that word in my bundled offline dictionary. Connect to the internet and retry for a broader lookup.",
                "awaiting_definition": True,
            }
        return 200, {
            "reply": format_definition_reply(query, definitions, mode),
            "awaiting_definition": False,
        }

    definitions = []
    network_unavailable = False
    with ThreadPoolExecutor(max_workers=min(8, len(words) or 1)) as executor:
        futures = {executor.submit(get_online_definition, word): word for word in words[:18]}
        for future in as_completed(futures):
            word = futures[future]
            word_definitions, reachable = future.result()
            network_unavailable = network_unavailable or not reachable
            if word_definitions:
                definitions.append((word, word_definitions))

    if not definitions and network_unavailable:
        return 503, {
            "error": "The online dictionary could not be reached.",
            "online_unavailable": True,
            "awaiting_definition": True,
        }
    if not definitions:
        return 200, {
            "reply": "I couldn’t find a definition for that in the online dictionary. Try a shorter word or rephrase the sentence.",
            "awaiting_definition": True,
        }
    for word, word_definitions in definitions:
        cache_online_definition(word, word_definitions)
    order = {word: index for index, word in enumerate(words)}
    definitions.sort(key=lambda item: order[item[0]])
    reply = format_definition_reply(query, definitions, mode)
    if network_unavailable:
        reply += "\n\nSome word lookups could not connect, so this sentence may have incomplete definitions."
    return 200, {"reply": reply, "awaiting_definition": False}


def handle_chat(payload):
    message = payload.get("message")
    if not isinstance(message, str) or not message.strip() or len(message) > 500:
        raise PracticeRequestError("message must contain between 1 and 500 characters.")
    message = message.strip()
    mode = payload.get("mode", "online")
    if mode not in ("online", "offline"):
        raise PracticeRequestError("mode must be online or offline.")
    awaiting_definition = payload.get("awaiting_definition") is True
    normalized = re.sub(r"[^a-z0-9\s]", "", message.lower()).strip()

    if re.fullmatch(r"(?:hi|hey|hello|hiya|howdy)(?: there)?", normalized):
        return 200, {
            "reply": "Hi! Nice to meet you. Need help with any definitions?",
            "awaiting_definition": True,
        }
    if normalized in ("yes", "yes please", "sure", "please", "yeah", "yep"):
        return 200, {
            "reply": "Sure! Tell me the word or sentence you want help understanding.",
            "awaiting_definition": True,
        }

    command = re.search(
        r"(?:help\s+me\s+with|help\s+with|definition\s+of|meaning\s+of|define|what\s+does|what\s+is)\s+(.+)",
        message,
        flags=re.IGNORECASE,
    )
    if command:
        query = command.group(1).strip().rstrip(" ?.!:")
        query = re.sub(r"\s+mean$", "", query, flags=re.IGNORECASE).strip()
    elif awaiting_definition:
        query = re.sub(
            r"^(?:yes[, ]+)?(?:please\s+)?(?:help\s+me\s+)?(?:with\s+)?",
            "",
            message,
            flags=re.IGNORECASE,
        ).strip().rstrip(" ?.!:")
    else:
        return 200, {
            "reply": "I can help with word and sentence definitions. Say hi, ask “what does ... mean?”, or tell me what you want defined.",
            "awaiting_definition": True,
        }

    if not query:
        return 200, {
            "reply": "What word or sentence should I explain?",
            "awaiting_definition": True,
        }
    return define_query(query, mode)


def assess_attempt(payload):
    target = payload.get("target")
    typed = payload.get("typed")
    focus = get_choice(payload, "focus", EXERCISES["easy"])
    elapsed_seconds = payload.get("elapsed_seconds")
    if not isinstance(target, str) or not target or len(target) > 500:
        raise PracticeRequestError("target must contain between 1 and 500 characters.")
    if not isinstance(typed, str) or not typed or len(typed) > 1_000:
        raise PracticeRequestError("typed must contain between 1 and 1,000 characters.")
    if (
        isinstance(elapsed_seconds, bool)
        or not isinstance(elapsed_seconds, (int, float))
        or not math.isfinite(elapsed_seconds)
        or elapsed_seconds < 0.5
        or elapsed_seconds > 3_600
    ):
        raise PracticeRequestError("elapsed_seconds must be between 0.5 and 3,600.")

    matcher = difflib.SequenceMatcher(None, target, typed, autojunk=False)
    matched_characters = sum(block.size for block in matcher.get_matching_blocks())
    accuracy = round(100 * matched_characters / max(len(target), len(typed)))
    wpm = round((matched_characters / 5) / (elapsed_seconds / 60))
    if accuracy >= 98:
        feedback = "Excellent accuracy. Try a harder exercise or keep building speed."
    elif accuracy >= 90:
        feedback = "Good work. Slow down slightly on the characters that felt tricky."
    else:
        feedback = "Focus on accuracy first: type at a comfortable pace and watch each word."
    if focus == "punctuation" and accuracy < 100:
        feedback += " Check commas, quotation marks, and sentence endings."
    elif focus == "numbers" and accuracy < 100:
        feedback += " Double-check each digit and symbol."
    elif focus == "speed" and accuracy >= 95:
        feedback += " Your accuracy is strong; try a slightly quicker rhythm."

    return {
        "accuracy": accuracy,
        "wpm": wpm,
        "matched_characters": matched_characters,
        "feedback": feedback,
    }


def main():
    server = ThreadingHTTPServer((HOST, PORT), PracticeServer)
    print(f"Typing game and practice coach running at http://{HOST}:{PORT}")
    print("Press Ctrl+C to stop the server.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping typing practice server.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

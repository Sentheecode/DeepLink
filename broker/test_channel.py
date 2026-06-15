import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from channel.main import load_env_file


class ChannelTests(unittest.TestCase):
    def test_load_env_file_supplies_missing_values_without_overwriting_process_env(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env_path = Path(directory) / "channel.env"
            env_path.write_text(
                "BROKER_URL=https://broker.example\n"
                "BROKER_TOKEN=from-file\n"
                "DEVICE_NAME=Mac Book\n",
                encoding="utf-8",
            )
            with patch.dict(os.environ, {"BROKER_TOKEN": "from-process"}, clear=True):
                load_env_file(env_path)

                self.assertEqual(os.environ["BROKER_URL"], "https://broker.example")
                self.assertEqual(os.environ["BROKER_TOKEN"], "from-process")
                self.assertEqual(os.environ["DEVICE_NAME"], "Mac Book")


if __name__ == "__main__":
    unittest.main()

"""Bounded self-play policy-gradient smoke on Planet Wars' private sprite wire."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.distributions import Categorical

from .env import PlanetWarsEnv
from .sprite_view import ACTION_MASKS, OBSERVATION_SIZE


class ActorCritic(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.actor = nn.Sequential(
            nn.Linear(OBSERVATION_SIZE, 128),
            nn.ReLU(),
            nn.Linear(128, len(ACTION_MASKS)),
        )
        self.critic = nn.Sequential(
            nn.Linear(OBSERVATION_SIZE, 128), nn.ReLU(), nn.Linear(128, 1)
        )

    def forward(self, observation: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        return self.actor(observation), self.critic(observation).squeeze(-1)


def train(
    bridge: Path, output: Path, seed: int, total_timesteps: int, episode_ticks: int
) -> None:
    torch.manual_seed(seed)
    model = ActorCritic()
    optimizer = torch.optim.Adam(model.parameters(), lr=3e-4)
    completed = 0
    episode = 0
    with PlanetWarsEnv(bridge) as env:
        while completed < total_timesteps:
            observation = env.reset(seed + episode, max_ticks=episode_ticks)
            log_probabilities = []
            values = []
            rewards = []
            entropies = []
            done = False
            while not done:
                features = torch.tensor(np.asarray(observation, dtype=np.float32))
                logits, value = model(features)
                choices = Categorical(logits=logits)
                actions = choices.sample()
                observation, reward, done, info = env.step(
                    tuple(int(action) for action in actions), repeat=6
                )
                log_probabilities.append(choices.log_prob(actions))
                values.append(value)
                rewards.append(torch.tensor(reward, dtype=torch.float32))
                entropies.append(choices.entropy())
            returns = []
            future = torch.zeros(8)
            for reward in reversed(rewards):
                future = reward + 0.99 * future
                returns.append(future)
            returns.reverse()
            target = torch.stack(returns)
            value = torch.stack(values)
            advantage = target - value
            policy_loss = -(torch.stack(log_probabilities) * advantage.detach()).mean()
            value_loss = advantage.square().mean()
            entropy = torch.stack(entropies).mean()
            loss = policy_loss + 0.5 * value_loss - 0.01 * entropy
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            completed += int(info["tick"]) * 8
            print(
                f"episode={episode} agent_steps={completed} scores={info['scores']} loss={loss.item():.4f}"
            )
            episode += 1
    output.parent.mkdir(parents=True, exist_ok=True)
    layers = (model.actor[0], model.actor[2])
    np.savez(
        output,
        w1=layers[0].weight.detach().numpy(),
        b1=layers[0].bias.detach().numpy(),
        w2=layers[1].weight.detach().numpy(),
        b2=layers[1].bias.detach().numpy(),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--total-timesteps", type=int, required=True)
    parser.add_argument("--episode-ticks", type=int, default=1200)
    args = parser.parse_args()
    if args.total_timesteps <= 0 or args.episode_ticks <= 0:
        parser.error("timestep limits must be positive")
    train(args.bridge, args.output, args.seed, args.total_timesteps, args.episode_ticks)


if __name__ == "__main__":
    main()

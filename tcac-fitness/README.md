# Time-Locked Community Accountability Contract (TCAC)

A Clarity smart contract for creating and managing accountability groups on the Stacks blockchain. This contract enables users to form time-locked groups, set goals, track progress, and earn rewards based on milestone completion.

## Overview

The TCAC smart contract implements a decentralized accountability system where users can:
- Create or join accountability groups
- Set and track personal milestones
- Stake tokens as commitment
- Verify other members' achievements
- Earn rewards based on completion
- Build reputation over time

## Features

### Group Management
- Create accountability groups with specific focus areas
- Join groups by staking STX tokens
- Maximum 10 members per group
- 90-day time-lock period
- Total stake pool tracking

### Milestone System
- Create personal milestones with deadlines
- Mark milestones as completed
- Community verification through voting
- Automated reward distribution
- Progress tracking and statistics

### Reward Mechanism
- Initial stake: 100 STX
- Rewards based on milestone completion rate
- Time-locked withdrawal period
- Reputation scoring system
- Protection against early withdrawal

## Contract Functions

### Public Functions

1. Group Creation and Management
```clarity
(create-group (name (string-ascii 64)) (focus-area (string-ascii 32)))
(join-group (group-id uint))
```

2. Milestone Management
```clarity
(add-milestone (group-id uint) (description (string-ascii 256)) (deadline uint))
(complete-milestone (group-id uint) (milestone-id uint))
(vote-milestone (group-id uint) (member principal) (milestone-id uint) (verify bool))
```

3. Reward Management
```clarity
(withdraw-rewards (group-id uint))
```

### Read-Only Functions

```clarity
(get-group-details (group-id uint))
(get-member-details (group-id uint) (member principal))
(get-milestone-details (group-id uint) (member principal) (milestone-id uint))
(get-reputation (member principal))
```

## Error Codes

| Code | Description |
|------|-------------|
| u100 | Not authorized |
| u101 | Group is full |
| u102 | Invalid stake amount |
| u103 | Group not found |
| u104 | Already a member |
| u105 | Not a member |
| u106 | Locked period |
| u107 | Milestone not found |
| u108 | Invalid vote |
| u109 | Already voted |
| u110 | Invalid name |
| u111 | Invalid focus area |
| u112 | Invalid group ID |
| u113 | Invalid description |
| u114 | Invalid deadline |

## Usage Example

1. Creating a New Group
```clarity
(contract-call? .fitness-accountability-v1 create-group "FitChain90" "Weight Training")
```

2. Joining a Group
```clarity
(contract-call? .fitness-accountability-v1 join-group u1)
```

3. Adding a Milestone
```clarity
(contract-call? .fitness-accountability-v1 add-milestone u1 "Complete 12 gym sessions" u100)
```

## Security Considerations

- Input validation for all parameters
- Time-locked periods enforced
- Protected stake withdrawal
- Community-based verification
- Minimum stake requirements
- Group size limitations

## Development

### Prerequisites
- Clarity CLI
- Stacks blockchain account
- Required STX tokens for deployment and testing

### Deployment
1. Clone the repository
2. Deploy using Clarinet or Stacks CLI
3. Initialize contract parameters
4. Verify deployment

## Testing

Recommended test scenarios:
1. Group creation and joining
2. Milestone management
3. Voting mechanism
4. Reward distribution
5. Edge cases and error handling
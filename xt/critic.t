use Test::Perl::Critic(-exclude => ['RequireFinalReturn',
											  'RequireArgUnpacking',
											  'ProhibitUnusedPrivateSubroutines',
											  'RequireExtendedFormatting',
											  'RequireCheckingReturnValueOfEval'],
							  -severity => 3);
all_critic_ok();

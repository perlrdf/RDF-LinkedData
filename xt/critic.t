use Test::Perl::Critic(-exclude => ['RequireFinalReturn',
											  'RequireArgUnpacking',
											  'ProhibitUnusedPrivateSubroutines',
											  'RequireExtendedFormatting',
											  'ProhibitExcessComplexity',
											  'RequireCheckingReturnValueOfEval'],
							  -severity => 3);
all_critic_ok();

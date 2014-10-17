use Test::Perl::Critic(-exclude => [
												'RequireFinalReturn',
											   'ProhibitUnusedPrivateSubroutines',
											   'RequireExtendedFormatting',
											   'ProhibitExcessComplexity',
											  ],
							  -severity => 3);
all_critic_ok();

use Test::Perl::Critic(-exclude => ['RequireFinalReturn',
											  'RequireArgUnpacking',
											  'ProhibitUnusedPrivateSubroutines',
											  'RequireExtendedFormatting',
											  'ProhibitExcessComplexity',
											  'RequireBlockGrep',
												'ProhibitCaptureWithoutTest',
											  ],
							  -severity => 3);
all_critic_ok();

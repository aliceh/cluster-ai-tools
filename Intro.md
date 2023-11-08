
# How can AI help us to be more productive in our daily tasks?



### Some popular AI models

https://www.simform.com/blog/open-source-llm/

Many models are shared in the community https://huggingface.co/

Meta's model LLAMA2 can be fine tuned now for customer's needs
And even trained on custom data:

https://github.com/facebookresearch/llama-recipes/blob/main/docs/Dataset.md#training-on-custom-data

OpenAI has an UI to create a GPT for your particular needs 


AWS Sage Maker - to train, fine tune your model


Experiment 

Q: "Explain this error: 2023-11-03 20:02:42 +0000 UTC hostedclusters rosa-lcjp7 router load balancer is not provisioned: (combined from similar events): Error syncing load balancer: failed to ensure load balancer: error authorizing security group ingress: "RulesPerSecurityGroupLimitExceeded: The maximum number of rules per security group has been reached."

A: The errors you've provided are related to a problem with setting up or managing load balancers in a cloud environment. Specifically, it appears to be an issue with the maximum number of security group rules that can be configured for the associated load balancers. Let's break down the error message:

"RulesPerSecurityGroupLimitExceeded: The maximum number of rules per security group has been reached."

This error indicates that there is a limit on the number of rules (or ingress rules) that can be added to a security group in your cloud infrastructure. A security group is a virtual firewall that controls the inbound and outbound traffic for resources like load balancers, instances, or virtual machines.
"status code: 400"

The "status code: 400" indicates that this is an HTTP error response, specifically, the "Bad Request" status code. This means that the request to add or modify the security group rules was invalid or couldn't be fulfilled because of the rule limit.
"request id: 7f29ed97-1bad-440f-ba5e-630ea549af22" and "request id: ee30450f-aa33-40b3-b6a8-a3280fa1c43d"

These are unique identifiers for the specific requests that resulted in the error. They can be useful for tracking down the specific actions that triggered the problem in your cloud infrastructure.
In summary, the errors you're seeing are due to a limitation in the number of security group rules that can be applied to your load balancers. To resolve this issue, you may need to review and optimize the existing security group rules, or consider splitting your resources into multiple security groups to avoid hitting this rule limit. Additionally, you may need to check your cloud provider's documentation or contact their support for guidance on how to work around or increase the rule limit if that is possible.


Usecase ideas:

- Train LLM on our documentation, and use it to address ustomer questions
- Train LLM on our errors 